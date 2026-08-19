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
        StreakWidget()
        AyahWidget()
    }
}

// MARK: - Next prayer

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: SajadahProvider()) { entry in
            NextPrayerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
            VStack(alignment: .leading, spacing: 2) {
                Label(next.prayer.displayName, systemImage: next.prayer.systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                // Ticks on its own, so the timeline needs no per-minute entries.
                Text(next.date, style: .relative)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(next.date, style: .time)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let place = entry.snapshot.placeName {
                    Text(place)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                .containerBackground(.fill.tertiary, for: .widget)
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

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.snapshot.placeName ?? "Today")
                        .font(.caption).fontWeight(.medium)
                    Spacer()
                    Text(day.hijri)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ForEach(DayLog.tracked, id: \.self) { prayer in
                    let time = day.time(for: prayer)
                    let isNext = next?.prayer == prayer
                    HStack(spacing: 6) {
                        Image(systemName: prayer.systemImage)
                            .font(.caption2)
                            .frame(width: 13)
                        Text(prayer.displayName)
                            .fontWeight(isNext ? .semibold : .regular)
                        Spacer(minLength: 4)
                        if entry.snapshot.state(for: prayer, at: entry.date) == .prayed {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        Text(time, style: .time)
                            .monospacedDigit()
                            .fontWeight(isNext ? .semibold : .regular)
                    }
                    .font(.caption)
                    // Past prayers recede so the next one reads at a glance.
                    .foregroundStyle(isNext ? .primary : (time < entry.date ? .tertiary : .secondary))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load prayer times.")
        }
    }
}

// MARK: - Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SajadahProvider()) { entry in
            StreakView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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

        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.title2)
                .foregroundStyle(streak > 0 ? .orange : .secondary)

            Text("\(streak)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(streak == 1 ? "day streak" : "day streak")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                ForEach(DayLog.tracked, id: \.self) { prayer in
                    Circle()
                        .fill(entry.snapshot.state(for: prayer, at: entry.date) == .prayed
                              ? Color.green : Color.secondary.opacity(0.25))
                        .frame(width: 9, height: 9)
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
                .containerBackground(.fill.tertiary, for: .widget)
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
                HStack {
                    Text("Ayah of the day")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ayah.surahEnglishName) \(ayah.ref.surah):\(ayah.ref.ayah)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Text(ayah.arabic)
                    .font(.arabic(ArabicFontChoice.defaultID, size: family == .systemLarge ? 22 : 17))
                    .lineSpacing(family == .systemLarge ? 10 : 7)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(family == .systemLarge ? 6 : 3)
                    .minimumScaleFactor(0.7)

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
        VStack(spacing: 6) {
            Image(systemName: "moon.stars")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
