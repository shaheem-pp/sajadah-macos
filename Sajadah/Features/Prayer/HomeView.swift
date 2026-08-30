//
//  HomeView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

/// The full window: today's timings plus the week ahead. Reads the same cache the menubar
/// popover does, so the two always agree.
struct HomeView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerLogStore.self) private var log
    @Environment(IqamahStore.self) private var iqamah

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if let day = store.today {
                    today(day)
                }

                iqamahCard
                streak
                weekAhead
            }
            .padding(22)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Theme.wellFill)
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if let next = store.nextEvent, let remaining = store.timeUntilNextEvent {
            NextPrayerHero(
                prayer: next.prayer,
                countdown: TimeFormatting.countdown(remaining),
                clock: TimeFormatting.clock(
                    next.date,
                    use24Hour: settings.use24HourClock,
                    timeZone: store.displayTimeZone
                ),
                place: store.placeName ?? "Current location",
                hijri: store.hijriDateText,
                isStale: store.isStale,
                progress: windowProgress
            )
        }
    }

    /// How much of the gap between the last timing and the next one has elapsed. Nil rather
    /// than zero when there is no previous event to measure from, so the bar disappears
    /// instead of reading as "no time has passed".
    private var windowProgress: Double? {
        guard let current = store.currentEvent, let next = store.nextEvent else { return nil }
        let span = next.date.timeIntervalSince(current.date)
        guard span > 0 else { return nil }
        return store.now.timeIntervalSince(current.date) / span
    }

    // MARK: Today

    private func today(_ day: DayTimings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Today", trailing: "\(log.prayedCount(on: store.todayKey)) of \(DayLog.tracked.count) prayed")

            PrayerListView(
                day: day,
                highlighted: store.nextEvent?.prayer,
                passedBefore: store.now,
                use24Hour: settings.use24HourClock,
                logging: PrayerLogging(
                    state: { log.state(for: $0, on: store.todayKey) },
                    cycle: { log.cycle($0, on: store.todayKey) }
                )
            )
            .sajadahCard(padding: 8)
        }
    }

    // MARK: Iqamah

    /// Only appears once a masjid is configured in Settings — same opt-in rule as the widget.
    /// These are static posted strings, not `Date`s, so unlike `today` there's no highlight or
    /// tap-to-log control here, just the values as the masjid published them.
    @ViewBuilder
    private var iqamahCard: some View {
        if let times = iqamah.times {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Iqamah", trailing: iqamah.sourceHost)

                VStack(spacing: 2) {
                    ForEach(DayLog.tracked, id: \.self) { prayer in
                        if let value = times.time(for: prayer) {
                            IqamahRow(prayer: prayer, value: value)
                        }
                    }
                }
                .sajadahCard(padding: 8)
            }
        }
    }

    // MARK: Streak

    private var streak: some View {
        let current = log.currentStreak(asOf: store.todayKey)
        let best = log.bestStreak
        let recent = log.recentDays(endingAt: store.todayKey, count: 30)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Streak", trailing: "Last 30 days")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    StreakStat(
                        value: current,
                        label: current == 1 ? "day" : "days",
                        systemImage: "flame.fill",
                        isEarned: current > 0
                    )
                    StreakStat(
                        value: best,
                        label: "best",
                        systemImage: "rosette",
                        isEarned: best > 0
                    )
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    ForEach(recent, id: \.dayKey) { entry in
                        DayCell(
                            prayed: entry.log?.prayed.count ?? 0,
                            isToday: entry.dayKey == store.todayKey
                        )
                        .help("\(entry.dayKey) — \(entry.log?.prayed.count ?? 0)/\(DayLog.tracked.count) prayed")
                    }
                }
            }
            .sajadahCard()
        }
    }

    // MARK: Week ahead

    @ViewBuilder
    private var weekAhead: some View {
        let days = store.days(from: store.now, count: 7)
        if days.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Next 7 days")

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text("Day").gridColumnAlignment(.leading)
                        ForEach(Prayer.allCases) { prayer in
                            Text(prayer.displayName)
                                .gridColumnAlignment(.trailing)
                                .foregroundStyle(prayer.isPrayer ? AnyShapeStyle(prayer.tint) : AnyShapeStyle(.tertiary))
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)

                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        GridRow {
                            Text(TimeFormatting.weekday(day.dhuhr, timeZone: day.timeZone))
                                .fontWeight(index == 0 ? .semibold : .regular)
                            ForEach(Prayer.allCases) { prayer in
                                Text(TimeFormatting.clock(
                                    day.time(for: prayer),
                                    use24Hour: settings.use24HourClock,
                                    timeZone: day.timeZone
                                ))
                                .monospacedDigit()
                                .foregroundStyle(prayer.isPrayer ? .primary : .tertiary)
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            // Today is called out; the rest alternate just enough to let the
                            // eye track a row across seven columns.
                            if index == 0 {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.jade.opacity(0.08))
                            } else if index.isMultiple(of: 2) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.wellFill)
                            }
                        }
                    }
                }
                .sajadahCard(padding: 8)
            }
        }
    }
}

// MARK: - Pieces

private struct StreakStat: View {
    let value: Int
    let label: String
    let systemImage: String
    let isEarned: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(isEarned ? Theme.brass : Color.secondary.opacity(0.5))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isEarned ? .primary : .secondary)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One posted Iqamah time. Echoes `PrayerRow`'s look (icon, name, time) without the
/// highlight/passed/log-button machinery that only makes sense for a countdown-driven time.
private struct IqamahRow: View {
    let prayer: Prayer
    let value: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: prayer.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(prayer.tint)
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(prayer.tint.opacity(0.09))
                }

            Text(prayer.displayName)
                .font(.system(size: 14))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14))
                .monospacedDigit()
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
    }
}

/// One day in the 30-day trail. A day where every prayer was logged earns the star rather
/// than a darker square — the shape changes, not just the value, so a complete day is
/// findable at a glance.
private struct DayCell: View {
    let prayed: Int
    let isToday: Bool

    private var isComplete: Bool { prayed >= DayLog.tracked.count }

    var body: some View {
        ZStack {
            if isComplete {
                RubElHizb().fill(Theme.jade)
            } else {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Theme.jade.opacity(prayed == 0 ? 0.07 : 0.16 + 0.13 * Double(prayed)))
            }

            if isToday {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Theme.jade.opacity(0.75), lineWidth: 1.2)
            }
        }
        .frame(width: 14, height: 14)
    }
}
