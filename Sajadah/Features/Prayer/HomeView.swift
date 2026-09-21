//
//  HomeView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

/// The full window: today's timings plus the week ahead. Reads the same cache the menubar
/// popover does, so the two always agree.
///
/// Two columns when there is room for them, one when there isn't. The left column is *now* —
/// the panel, the day's rows and the week ahead, the things you act on; the right is the
/// *record* — the streak, the fasts ahead, the verse. A window narrower than that reads top
/// to bottom in the same order.
///
/// The two columns end on the same line. The stack proposes the taller column's height to
/// the shorter one, and each column has one card that is allowed to take it: the week table
/// on the left, whose rows spread to fill, and the verse on the right. The panel used to be
/// what stretched — several hundred points of sky doing the job of a spacer — which is why it
/// now pins itself to its words and the week table sits under Today instead of under both.
struct HomeView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerLogStore.self) private var log
    @Environment(IqamahStore.self) private var iqamah
    @Environment(QuranStore.self) private var quran
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings

    /// The scroll view's width, which decides how many columns the page gets.
    @State private var width: CGFloat = 0

    private static let inset: CGFloat = 22
    private static let gap: CGFloat = 18
    /// The record column is fixed: the streak calendar and a verse at reading size both sit
    /// comfortably in it, and a column that grew with the window would starve the rows.
    private static let sideColumnWidth: CGFloat = 340
    /// Two columns need the side column plus a left column wide enough for the week table's
    /// seven columns to stay readable — about 64 points each for a 12-hour time.
    private static let twoColumnMinWidth: CGFloat = 960
    private static let maxContentWidth: CGFloat = 1080

    private var isWide: Bool { width - 2 * Self.inset >= Self.twoColumnMinWidth }

    var body: some View {
        // Derived once and handed down: the panel and the table have to be describing the
        // same moment, and asking twice invites them to drift a tick apart.
        let phase = store.phase(iqamah: iqamah.times, log: log.days)

        return ScrollView {
            Group {
                if isWide {
                    wide(phase)
                } else {
                    narrow(phase)
                }
            }
            .padding(Self.inset)
            .frame(maxWidth: Self.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Theme.wellFill)
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: Layouts

    private func wide(_ phase: DayPhase) -> some View {
        HStack(alignment: .top, spacing: Self.gap) {
            VStack(alignment: .leading, spacing: Self.gap) {
                hero(phase)
                if let day = store.today {
                    today(day, phase: phase)
                }
                weekAhead
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Self.gap) {
                streak
                fasting
                ayahOfTheDay
            }
            .frame(width: Self.sideColumnWidth)
        }
    }

    private func narrow(_ phase: DayPhase) -> some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            hero(phase)
            if let day = store.today {
                today(day, phase: phase)
            }
            weekAhead
            streak
            fasting
            ayahOfTheDay
        }
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
            fasting: store.fastingBadge,
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

            // Not a `SettingsLink`: that opens whichever pane was last used, and an invite
            // to add a masjid should land on the form that adds one.
            Button("Set Up…") {
                navigation.settingsPane = .masjid
                openSettings()
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
        let stats = [
            StreakStat(value: current, label: current == 1 ? "day" : "days", systemImage: "flame.fill", isEarned: current > 0),
            StreakStat(value: best, label: "best", systemImage: "rosette", isEarned: best > 0),
        ]

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Streak", trailing: "Last 5 weeks")

            // Stats beside the calendar where the card is wide enough — the side column is,
            // just — and above it where it isn't, rather than squeezing either.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(stats, id: \.label) { $0 }
                    }
                    Spacer(minLength: 24)
                    StreakCalendar()
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 22) {
                        ForEach(stats, id: \.label) { $0 }
                    }
                    StreakCalendar()
                }
            }
            .sajadahCard()
        }
    }

    // MARK: Fasting

    /// The fasts ahead once the feature is on. Off by default, so until then the same slot
    /// says it exists — once, and where the card would appear. No first-launch wizard: a
    /// menubar app's first job is the next prayer, now.
    @ViewBuilder
    private var fasting: some View {
        if settings.fastingEnabled {
            FastingCard()
        } else if !settings.fastingInviteDismissed {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Fasting")
                fastingInvite
            }
        }
    }

    private var fastingInvite: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "fork.knife")
                .font(.system(size: 11))
                .foregroundStyle(Theme.jade)
                .padding(.top, 2)

            Text("Mark sunnah fasting days — Mondays, Thursdays, the white days, Ashura and Arafah — beside the Hijri date, with a reminder the evening before.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Turn On…") {
                navigation.settingsPane = .fasting
                openSettings()
            }
            .controlSize(.small)

            Button {
                settings.fastingInviteDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide this")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .sajadahCard(padding: 0)
    }

    // MARK: Week ahead

    @ViewBuilder
    private var weekAhead: some View {
        let days = store.days(from: store.now, count: 7)
        if days.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Next 7 days")

                // Every time cell is flexible both ways. Across, so the columns share the
                // card's width rather than the card shrinking to them; down, so the rows
                // share whatever height the column has spare — this is the card that levels
                // the left column with the right. The Day column keeps its natural width: it
                // is the one with words in it, and "Wed 23 Sep" was the first thing to
                // truncate when it had to split the width six ways with the times.
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text("Day")
                            .fixedSize()
                        ForEach(Prayer.allCases) { prayer in
                            Text(prayer.displayName)
                                .foregroundStyle(prayer.isPrayer ? AnyShapeStyle(prayer.tint) : AnyShapeStyle(.tertiary))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)

                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        GridRow {
                            dayLabel(day, isToday: index == 0)
                            ForEach(Prayer.allCases) { prayer in
                                Text(TimeFormatting.clock(
                                    day.time(for: prayer),
                                    use24Hour: settings.use24HourClock,
                                    timeZone: day.timeZone
                                ))
                                .monospacedDigit()
                                .foregroundStyle(prayer.isPrayer ? .primary : .tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
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

    /// The day, with a mark on the ones that are fasts — the same brass the hero uses for
    /// its label, small enough to be a flag rather than a column.
    private func dayLabel(_ day: DayTimings, isToday: Bool) -> some View {
        let reasons = store.fastingStatus(on: day.dayKey)?.reasons ?? []

        return HStack(spacing: 5) {
            Text(TimeFormatting.weekday(day.dhuhr, timeZone: day.timeZone))
                .fontWeight(isToday ? .semibold : .regular)

            if !reasons.isEmpty {
                Image(systemName: "fork.knife")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.brass)
                    .help("Fasting day · \(reasons.joined)")
            }
        }
        .fixedSize()
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Ayah of the day

    /// The bridge from the prayer half of the window to the Quran half. Absent rather than
    /// empty until the day's verse has loaded, as in the popover.
    @ViewBuilder
    private var ayahOfTheDay: some View {
        if let daily = quran.dailyAyah {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: "Ayah of the day",
                    trailing: "\(daily.surahEnglishName) \(daily.ref.surah):\(daily.ref.ayah)"
                )

                AyahOfTheDayView(ayah: daily, arabicFont: settings.arabicFontName, style: .card) {
                    // In-window: the sidebar and detail both follow `navigation.selection`,
                    // so this lands in the reader at the ayah with no window to bring forward.
                    navigation.open(daily.ref)
                }
                // The right column's levelling card, as the week table is the left's. Room
                // under a verse is the least awkward place for any to end up.
                .frame(maxHeight: .infinity, alignment: .top)
                .sajadahCard()
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
