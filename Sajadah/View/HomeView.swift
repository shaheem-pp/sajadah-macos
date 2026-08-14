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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let day = store.today {
                    GroupBox("Today") {
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
                        .padding(4)
                    }
                }

                history
                weekAhead
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.placeName ?? "Current location")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                if store.isStale {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let hijri = store.hijriDateText {
                Text(hijri)
                    .foregroundStyle(.secondary)
            }

            if let next = store.nextEvent, let remaining = store.timeUntilNextEvent {
                HStack(spacing: 6) {
                    Image(systemName: next.prayer.systemImage)
                    Text("\(next.prayer.displayName) in \(TimeFormatting.countdown(remaining))")
                        .monospacedDigit()
                    Text("·")
                    Text(TimeFormatting.clock(
                        next.date,
                        use24Hour: settings.use24HourClock,
                        timeZone: store.displayTimeZone
                    ))
                }
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }
        }
    }

    // MARK: History

    private var history: some View {
        let streak = log.currentStreak(asOf: store.todayKey)
        let best = log.bestStreak
        let recent = log.recentDays(endingAt: store.todayKey, count: 30)

        return GroupBox("Streak") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    StreakStat(
                        value: streak,
                        label: streak == 1 ? "day streak" : "day streak",
                        systemImage: "flame.fill",
                        tint: streak > 0 ? .orange : .secondary
                    )
                    StreakStat(
                        value: best,
                        label: "best",
                        systemImage: "trophy.fill",
                        tint: best > 0 ? .yellow : .secondary
                    )
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(recent, id: \.dayKey) { entry in
                            let count = entry.log?.prayed.count ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.accentColor.opacity(count == 0 ? 0.08 : 0.25 + 0.15 * Double(count)))
                                .frame(width: 14, height: 14)
                                .help("\(entry.dayKey) — \(count)/\(DayLog.tracked.count) prayed")
                        }
                    }
                    Text("Last 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    // MARK: Week ahead

    @ViewBuilder
    private var weekAhead: some View {
        let days = store.days(from: store.now, count: 7)
        if days.count > 1 {
            GroupBox("Next 7 days") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Day")
                            .gridColumnAlignment(.leading)
                        ForEach(Prayer.allCases) { prayer in
                            Text(prayer.displayName)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider().gridCellUnsizedAxes(.horizontal)

                    ForEach(days) { day in
                        GridRow {
                            Text(TimeFormatting.weekday(day.dhuhr, timeZone: day.timeZone))
                            ForEach(Prayer.allCases) { prayer in
                                Text(TimeFormatting.clock(
                                    day.time(for: prayer),
                                    use24Hour: settings.use24HourClock,
                                    timeZone: day.timeZone
                                ))
                                .monospacedDigit()
                                .foregroundStyle(prayer.isPrayer ? .primary : .secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(6)
            }
        }
    }
}

private struct StreakStat: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
