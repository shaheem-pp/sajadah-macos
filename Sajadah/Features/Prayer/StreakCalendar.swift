//
//  StreakCalendar.swift
//  Sajadah
//

import SwiftUI

/// Five weeks of days, laid out as a calendar: one row per week, columns in the user's
/// weekday order, today at the end of the last row and the rest of that week left blank.
///
/// A calendar rather than a strip because the squares are clickable now. "Last Friday" is a
/// glance on a calendar and a hover-and-count on a strip of thirty identical cells.
struct StreakCalendar: View {
    @Environment(PrayerLogStore.self) private var log
    @Environment(PrayerTimesStore.self) private var store

    /// The day whose editor is open, if any.
    @State private var editingDayKey: String?

    private static let weeks = 5
    private static let cell: CGFloat = 18
    private static let gap: CGFloat = 5

    var body: some View {
        let todayKey = store.todayKey
        let layout = layout(endingAt: todayKey, timeZone: store.displayTimeZone)

        Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            GridRow {
                ForEach(Array(layout.initials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.cell)
                }
            }

            ForEach(layout.weeks, id: \.first!.dayKey) { week in
                GridRow {
                    ForEach(week, id: \.dayKey) { entry in
                        if entry.dayKey > todayKey {
                            // The rest of this week: not a day yet, so not a button.
                            Color.clear.frame(width: Self.cell, height: Self.cell)
                        } else {
                            cell(entry, isToday: entry.dayKey == todayKey)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ entry: (dayKey: String, log: DayLog?), isToday: Bool) -> some View {
        let title = dayTitle(entry.dayKey)
        let prayed = entry.log?.prayed.count ?? 0

        return Button {
            editingDayKey = entry.dayKey
        } label: {
            DayCell(prayed: prayed, isToday: isToday, size: Self.cell)
        }
        .buttonStyle(.plain)
        .help("\(title) — \(prayed)/\(DayLog.tracked.count) prayed. Click to edit.")
        .popover(isPresented: editorBinding(for: entry.dayKey), arrowEdge: .bottom) {
            DayLogEditor(
                dayKey: entry.dayKey,
                title: title,
                loggable: loggablePrayers(on: entry.dayKey)
            )
        }
    }

    // MARK: Layout

    private struct Layout {
        let initials: [String]
        let weeks: [[(dayKey: String, log: DayLog?)]]
    }

    /// Rows of seven ending with the week that holds `todayKey`, in the locale's weekday order.
    /// Nothing else in the app asks which day a week starts on, so the locale is consulted
    /// here and nowhere else.
    private func layout(endingAt todayKey: String, timeZone: TimeZone) -> Layout {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone

        let daysToWeekEnd: Int
        if let today = DayKey.date(todayKey, in: timeZone) {
            let weekday = calendar.component(.weekday, from: today)
            daysToWeekEnd = (calendar.firstWeekday + 6 - weekday + 7) % 7
        } else {
            daysToWeekEnd = 0
        }
        let endKey = DayKey.shifted(todayKey, by: daysToWeekEnd) ?? todayKey

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        let initials = (0..<7).map { symbols[(start + $0) % 7] }

        let entries = log.recentDays(endingAt: endKey, count: Self.weeks * 7)
        let rows = stride(from: 0, to: entries.count, by: 7).map { Array(entries[$0..<min($0 + 7, entries.count)]) }
        return Layout(initials: initials, weeks: rows)
    }

    // MARK: Editing

    private func editorBinding(for dayKey: String) -> Binding<Bool> {
        Binding(
            get: { editingDayKey == dayKey },
            set: { if !$0 { editingDayKey = nil } }
        )
    }

    private func dayTitle(_ dayKey: String) -> String {
        DayKey.date(dayKey, in: store.displayTimeZone)
            .map { TimeFormatting.weekday($0, timeZone: store.displayTimeZone) } ?? dayKey
    }

    /// The calendar never offers a future day, so anything but today is fully loggable. Today
    /// keeps the list's rule: a prayer can be logged only once its time has come.
    private func loggablePrayers(on dayKey: String) -> Set<Prayer> {
        guard dayKey == store.todayKey else { return Set(DayLog.tracked) }
        guard let today = store.today else { return [] }
        return Set(DayLog.tracked.filter { today.time(for: $0) < store.now })
    }
}

// MARK: - Cell

/// One day. A day where every prayer was logged earns the star rather than a darker square —
/// the shape changes, not just the value, so a complete day is findable at a glance.
private struct DayCell: View {
    let prayed: Int
    let isToday: Bool
    var size: CGFloat = 14

    private var isComplete: Bool { prayed >= DayLog.tracked.count }

    var body: some View {
        ZStack {
            if isComplete {
                RubElHizb().fill(Theme.jade)
            } else {
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .fill(Theme.jade.opacity(prayed == 0 ? 0.07 : 0.16 + 0.13 * Double(prayed)))
            }

            if isToday {
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .strokeBorder(Theme.jade.opacity(0.75), lineWidth: 1.2)
            }
        }
        .frame(width: size, height: size)
    }
}
