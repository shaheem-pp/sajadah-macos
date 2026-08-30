//
//  SajadahWidgets.swift
//  SajadahWidgets
//
//  On macOS 14+ desktop widgets and Notification Center widgets are the same WidgetKit
//  widget — the system decides placement — so one bundle serves both.
//

import SwiftUI
import WidgetKit

@main
struct SajadahWidgetBundle: WidgetBundle {
    init() {
        // The ayah widget renders Uthmani text, and the extension has its own bundle, so it
        // must register the font itself rather than relying on the app having done it.
        BundledFonts.registerAll()
    }

    var body: some Widget {
        NextPrayerWidget()
        PrayerTimesWidget()
        IqamahWidget()
        StreakWidget()
        AyahWidget()
    }
}

// MARK: - Backgrounds

/// The quiet background: the system's own widget fill with the khatim lattice over it.
private struct LatticeBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            StarLattice(spacing: 34, lineWidth: 0.7)
        }
    }
}

/// The same hour-of-day wash the app's hero uses, so a widget on the desktop and the popover
/// in the menubar are recognisably the same thing.
private struct SkyBackground: View {
    let prayer: Prayer?

    var body: some View {
        ZStack {
            if let prayer {
                prayer.sky
                LinearGradient(
                    colors: [.black.opacity(0.30), .black.opacity(0.02)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                StarLattice(spacing: 32, color: Theme.ornamentOnSky, lineWidth: 0.7)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
    }
}

// MARK: - Next prayer

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: SajadahProvider()) { entry in
            NextPrayerView(entry: entry)
                .containerBackground(for: .widget) {
                    SkyBackground(prayer: entry.snapshot.nextEvent(after: entry.date)?.prayer)
                }
                .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Next Prayer")
        .description("Counts down to the next prayer.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextPrayerView: View {
    let entry: SajadahEntry

    var body: some View {
        if let next = entry.snapshot.nextEvent(after: entry.date) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                    Spacer(minLength: 0)
                    Image(systemName: next.prayer.systemImage)
                        .font(.system(size: 12, weight: .light))
                }
                .foregroundStyle(.white.opacity(0.72))

                Spacer(minLength: 4)

                Text(next.prayer.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                // Ticks on its own, so the timeline needs no per-minute entries.
                Text(next.date, style: .relative)
                    .font(.system(size: 25, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(next.date, style: .time)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.80))

                Spacer(minLength: 2)

                if let place = entry.snapshot.placeName {
                    Text(place)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load prayer times.")
        }
    }
}

// MARK: - Today's timings

struct PrayerTimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerTimes", provider: SajadahProvider()) { entry in
            PrayerTimesView(entry: entry)
                .containerBackground(for: .widget) { LatticeBackground() }
                .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Today’s Prayers")
        .description("All five prayers for today, with the next one highlighted.")
        .supportedFamilies([.systemMedium])
    }
}

struct PrayerTimesView: View {
    let entry: SajadahEntry

    var body: some View {
        if let day = entry.snapshot.today(at: entry.date) {
            let next = entry.snapshot.nextEvent(after: entry.date)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    RubElHizb()
                        .fill(Theme.jade.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Text(entry.snapshot.placeName ?? "Today")
                        .font(.caption).fontWeight(.medium)
                    Spacer(minLength: 6)
                    Text(day.hijri)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 1)

                ForEach(DayLog.tracked, id: \.self) { prayer in
                    let time = day.time(for: prayer)
                    let isNext = next?.prayer == prayer
                    let hasPassed = time < entry.date

                    HStack(spacing: 7) {
                        Image(systemName: prayer.systemImage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(hasPassed && !isNext ? prayer.tint.opacity(0.55) : prayer.tint)
                            .frame(width: 16, height: 16)
                            .background {
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .fill(prayer.tint.opacity(isNext ? 0.16 : 0.09))
                            }

                        Text(prayer.displayName)
                            .fontWeight(isNext ? .semibold : .regular)

                        Spacer(minLength: 4)

                        if entry.snapshot.state(for: prayer, at: entry.date) == .prayed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.jade)
                        }

                        Text(time, style: .time)
                            .monospacedDigit()
                            .fontWeight(isNext ? .semibold : .regular)
                    }
                    .font(.caption)
                    // Past prayers recede so the next one reads at a glance.
                    .foregroundStyle(isNext ? .primary : (hasPassed ? .tertiary : .secondary))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        if isNext {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(prayer.tint.opacity(0.13))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load prayer times.")
        }
    }
}

// MARK: - Masjid Iqamah times

struct IqamahWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IqamahTimes", provider: SajadahProvider()) { entry in
            IqamahWidgetView(entry: entry)
                .containerBackground(for: .widget) { LatticeBackground() }
                .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Masjid Iqamah Times")
        .description("Congregation prayer times for your local masjid, as posted on its website.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct IqamahWidgetView: View {
    let entry: SajadahEntry

    var body: some View {
        if let times = entry.snapshot.iqamah {
            // Adhan times for the same day, paired in alongside Iqamah where available — nil
            // once cached data is thin, in which case rows just fall back to Iqamah alone.
            let day = entry.snapshot.today(at: entry.date)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    RubElHizb()
                        .fill(Theme.jade.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Text("IQAMAH")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                    Spacer(minLength: 6)
                    if let host = entry.snapshot.iqamahSourceHost {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 1)

                ForEach(DayLog.tracked, id: \.self) { prayer in
                    if let value = times.time(for: prayer) {
                        IqamahWidgetRow(label: prayer.displayName, athaan: day?.time(for: prayer), iqamah: value)
                    }
                }
                if let jummah1 = times.jummah1 {
                    IqamahWidgetRow(label: "1st Jummah", athaan: nil, iqamah: jummah1)
                }
                if let jummah2 = times.jummah2 {
                    IqamahWidgetRow(label: "2nd Jummah", athaan: nil, iqamah: jummah2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Set your masjid in Settings to see Iqamah times.")
        }
    }
}

/// One row: label, then Adhan → Iqamah when both are known — same "Adhan then Iqamah" pairing
/// as the menubar badge, rather than showing Iqamah on its own with no anchor. Jummah has no
/// Adhan counterpart, so `athaan` is simply nil for those two rows and only Iqamah shows.
private struct IqamahWidgetRow: View {
    let label: String
    let athaan: Date?
    /// A posted string, not a `Date` — see `IqamahTimes`.
    let iqamah: String

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let athaan {
                Text(athaan, style: .time)
                    .foregroundStyle(.secondary)
            }
            Text(iqamah)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

// MARK: - Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SajadahProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(for: .widget) { LatticeBackground() }
                .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Prayer Streak")
        .description("Your current streak and today’s progress.")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakView: View {
    let entry: SajadahEntry

    var body: some View {
        let streak = entry.snapshot.currentStreak(at: entry.date)

        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.title2)
                .foregroundStyle(streak > 0 ? Theme.brass : .secondary)

            Spacer(minLength: 2)

            Text("\(streak)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
            Text(streak == 1 ? "day streak" : "day streak")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            // One star per prayer, filled as the day is logged.
            HStack(spacing: 5) {
                ForEach(DayLog.tracked, id: \.self) { prayer in
                    let prayed = entry.snapshot.state(for: prayer, at: entry.date) == .prayed
                    RubElHizb()
                        .fill(prayed ? Theme.jade : Color.secondary.opacity(0.22))
                        .frame(width: 11, height: 11)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Ayah of the day

struct AyahWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AyahOfTheDay", provider: SajadahProvider()) { entry in
            AyahWidgetView(entry: entry)
                .containerBackground(for: .widget) { LatticeBackground() }
        }
        .configurationDisplayName("Ayah of the Day")
        .description("A verse each day, with its translation.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AyahWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SajadahEntry

    var body: some View {
        if let ayah = entry.snapshot.dailyAyah {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    RubElHizb()
                        .fill(Theme.jade.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Text("AYAH OF THE DAY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text("\(ayah.surahEnglishName) \(ayah.ref.surah):\(ayah.ref.ayah)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Text(ayah.arabic)
                    .font(.arabic(ArabicFontChoice.defaultID, size: family == .systemLarge ? 22 : 17))
                    .lineSpacing(family == .systemLarge ? 10 : 7)
                    // `.leading` is the right edge inside the right-to-left environment
                    // below; asking for `.trailing` flushes Arabic to the left.
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(family == .systemLarge ? 6 : 3)
                    .minimumScaleFactor(0.7)

                if family == .systemLarge {
                    OrnamentDivider()
                }

                Text(ayah.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemLarge ? 8 : 3)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(SajadahLink.ayah(ayah.ref))
        } else {
            WidgetEmptyView(message: "Open Sajadah to load the Quran.")
                .widgetURL(SajadahLink.today)
        }
    }
}

// MARK: - Shared empty state

/// Shown when the shared container has no data — either the app hasn't run yet, or the App
/// Group isn't wired up, in which case the widget genuinely cannot see anything.
struct WidgetEmptyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                MihrabArch().fill(Theme.jade.opacity(0.07))
                MihrabArch().stroke(Theme.jade.opacity(0.28), lineWidth: 1)
                Image(systemName: "moon.stars")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Theme.jade)
                    .padding(.top, 10)
            }
            .frame(width: 38, height: 47)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
