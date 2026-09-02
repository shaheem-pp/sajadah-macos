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
        // Derived once and handed down: the panel and the table have to be describing the
        // same moment, and asking twice invites them to drift a tick apart.
        let phase = store.phase(
            iqamah: iqamah.times,
            dayIsComplete: log.isComplete(store.todayKey)
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(phase)

                if let day = store.today {
                    today(day, phase: phase)
                }

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

    /// The panel words itself from the phase — waiting for an Adhan, waiting for a jamaah,
    /// inside a window, or done for the day.
    @ViewBuilder
    private func hero(_ phase: DayPhase) -> some View {
        if let panel = NextPrayerHero(
            phase: phase,
            now: store.now,
            use24Hour: settings.use24HourClock,
            timeZone: store.displayTimeZone,
            place: store.placeName ?? "Current location",
            hijri: store.hijriDateText,
            isStale: store.isStale
        ) {
            panel
        }
    }

    // MARK: Today

    private func today(_ day: DayTimings, phase: DayPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Today", trailing: "\(log.prayedCount(on: store.todayKey)) of \(DayLog.tracked.count) prayed")

            VStack(spacing: 0) {
                PrayerListView(
                    day: day,
                    highlighted: Self.highlighted(for: phase),
                    passedBefore: store.now,
                    use24Hour: settings.use24HourClock,
                    // Nil until a masjid is configured, which keeps the list single-column —
                    // the same opt-in rule the widget uses.
                    iqamah: iqamah.times,
                    iqamahSource: iqamahSourceCaption,
                    logging: PrayerLogging(
                        state: { log.state(for: $0, on: store.todayKey) },
                        cycle: { log.cycle($0, on: store.todayKey) }
                    )
                )

                if iqamah.times == nil {
                    masjidInvite
                }
            }
            .sajadahCard(padding: 8)
        }
    }

    /// What the Jamaah column says about where its times came from. A scraped page is named by
    /// its host; computed times have no source to name, so they say what they are instead.
    private var iqamahSourceCaption: String? {
        guard iqamah.times != nil else { return nil }
        return switch settings.iqamahSourceMode {
        case .website: iqamah.sourceHost
        case .offset: "after Adhan"
        }
    }

    /// Until a masjid is set the Jamaah column simply isn't there, and nothing anywhere says
    /// it could be. The invite goes in the column's own place rather than in Settings, so the
    /// feature asks for itself where its answer would appear.
    private var masjidInvite: some View {
        HStack(spacing: 9) {
            Image(systemName: "building.columns")
                .font(.system(size: 11))
                .foregroundStyle(Theme.jade)

            Text("Add your masjid to see its jamaah times here.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            SettingsLink {
                Text("Set Up…")
            }
            .controlSize(.small)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 2)
        }
    }

    /// Which row to call out. Inside a window — and especially while its jamaah is still
    /// ahead — that's the prayer you are currently in, not the one after it, so the table
    /// marks the same prayer the panel above is counting down to. A finished day marks
    /// nothing: there is no longer a row waiting on you.
    private static func highlighted(for phase: DayPhase) -> Prayer? {
        switch phase {
        case .awaitingAdhan(let next): next.prayer
        case .awaitingIqamah(let prayer, _, _): prayer
        case .inWindow(let prayer, _, _): prayer
        case .dayComplete, .unavailable: nil
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
