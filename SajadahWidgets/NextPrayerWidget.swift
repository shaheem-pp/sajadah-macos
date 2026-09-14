//
//  NextPrayerWidget.swift
//  SajadahWidgets
//

import SwiftUI
import WidgetKit

/// The one thing the app exists to answer, on the desktop: how long until the Adhan, whether
/// jamaah is still catchable, or how much of the window is left — worded by the same
/// `DayPhase` the app's hero uses, so the two can't describe one moment differently.
///
/// Small is the answer alone. Medium adds the day: the five prayers on one rule, so what
/// comes after this one is in the same glance.
struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: SajadahProvider()) { entry in
            FamilyReader { family in
                NextPrayerView(entry: entry, family: family)
            }
            .widgetTimeZone(entry.snapshot)
            .containerBackground(for: .widget) {
                SkyBackground(prayer: entry.snapshot.phase(at: entry.date).prayer)
            }
            .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Next Prayer")
        .description("Counts down to the next prayer, the jamaah, or the end of the window.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextPrayerView: View {
    let entry: SajadahEntry
    let family: WidgetFamily

    var body: some View {
        let phase = entry.snapshot.phase(at: entry.date)
        if let copy = PhaseCopy(phase: phase, at: entry.date) {
            HStack(alignment: .top, spacing: 14) {
                headline(copy)
                    .frame(maxWidth: family == .systemMedium ? 150 : .infinity, alignment: .leading)

                if family == .systemMedium {
                    DayStrip(snapshot: entry.snapshot, date: entry.date, ink: .onSky, glyphSize: 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load prayer times.")
        }
    }

    /// Kicker, title, the ticking figure, and the clock time it is heading for.
    private func headline(_ copy: PhaseCopy) -> some View {
        let ink = Ink.onSky
        return VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(title: copy.kicker, ink: .onSky)

            Spacer(minLength: 4)

            Text(copy.title)
                .font(.system(size: family == .systemSmall ? 18 : 20, weight: .semibold))
                .foregroundStyle(ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let target = copy.target {
                Countdown(from: entry.date, to: target, size: family == .systemSmall ? 30 : 32)
            } else {
                Text(copy.fallback)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                if let prefix = copy.clockPrefix {
                    Text(prefix)
                }
                if let target = copy.target {
                    Text(target, style: .time)
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(ink.secondary)
            .lineLimit(1)

            if let progress = copy.progress {
                WindowBar(fraction: progress, urgent: copy.isUrgent)
                    .padding(.top, 6)
                    .padding(.trailing, family == .systemSmall ? 34 : 0)
            }

            Spacer(minLength: 4)

            if let place = entry.snapshot.placeName {
                Text(place)
                    .font(.system(size: 9.5))
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .padding(.trailing, family == .systemSmall ? 34 : 0)
            }
        }
    }
}

// MARK: - Wording

/// The words for each phase, in the widget's register: the same kicker and title the app's
/// hero uses, with the countdown left to `Text(timerInterval:)` rather than pre-formatted.
struct PhaseCopy {
    let kicker: String
    let title: String
    /// What the figure counts down to. Nil for a finished day with no tomorrow loaded.
    let target: Date?
    /// "until", where the clock time is a window's close rather than a start.
    let clockPrefix: String?
    /// Shown instead of a countdown when there is no target.
    let fallback: String
    let progress: Double?
    /// The minutes before a jamaah — the one point in the day where being late is a
    /// different outcome rather than a later one. Draws a brighter edge.
    let isUrgent: Bool

    private static let urgentLead: TimeInterval = 15 * 60

    init?(phase: DayPhase, at now: Date) {
        switch phase {
        case .awaitingAdhan(let next):
            kicker = "Next prayer"
            title = next.prayer.displayName
            target = next.date
            clockPrefix = nil
            fallback = ""
            progress = nil
            isUrgent = false

        case .awaitingIqamah(let prayer, _, let iqamah):
            kicker = "At the masjid"
            title = "\(prayer.displayName) jamaah"
            target = iqamah
            clockPrefix = nil
            fallback = ""
            progress = phase.progress(at: now)
            isUrgent = iqamah.timeIntervalSince(now) <= Self.urgentLead

        case .inWindow(let prayer, _, let closesAt):
            kicker = "In the window"
            title = prayer.displayName
            target = closesAt
            clockPrefix = "until"
            fallback = ""
            progress = phase.progress(at: now)
            isUrgent = false

        case .dayComplete(let next):
            kicker = "Day complete"
            title = "All five prayed"
            target = next?.date
            clockPrefix = next.map { "\($0.prayer.displayName) at" }
            fallback = "Tomorrow's times aren't loaded yet"
            progress = nil
            isUrgent = false

        case .unavailable:
            return nil
        }
    }
}
