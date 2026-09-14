//
//  PrayerLogWidget.swift
//  SajadahWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

/// Today's five as a ring that closes when the day is done, and the streak it feeds. Medium
/// adds a button per prayer, so logging happens on the desktop rather than in the app — the
/// question the app otherwise has to ask with a notification.
struct PrayerLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SajadahProvider()) { entry in
            FamilyReader { family in
                PrayerLogView(entry: entry, family: family)
            }
            .widgetTimeZone(entry.snapshot)
            .containerBackground(for: .widget) { LatticeBackground() }
            .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Prayer Log")
        .description("Today's prayers as a ring, your streak, and a button to log each one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PrayerLogView: View {
    let entry: SajadahEntry
    let family: WidgetFamily

    var body: some View {
        let snapshot = entry.snapshot
        let prayed = snapshot.prayedCount(at: entry.date)
        let streak = snapshot.currentStreak(at: entry.date)

        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                WidgetKicker(title: "Prayer log", trailing: Text("\(prayed) of \(DayLog.tracked.count)"))
                Spacer(minLength: 2)
                ring(prayed: prayed, size: 74, lineWidth: 6.5)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 2)
                streakLine(streak)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WidgetKicker(title: "Prayer log", trailing: streakBadge(streak))

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 14) {
                    ring(prayed: prayed, size: 78, lineWidth: 7)

                    HStack(spacing: 5) {
                        ForEach(DayLog.tracked, id: \.self) { prayer in
                            LogButton(prayer: prayer, entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func ring(prayed: Int, size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            PrayerRing(snapshot: entry.snapshot, date: entry.date, size: size, lineWidth: lineWidth)
            VStack(spacing: -2) {
                Text("\(prayed)")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(DayLog.tracked.count)")
                    .font(.system(size: size * 0.13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(prayed) of \(DayLog.tracked.count) prayed")
    }

    private func streakLine(_ streak: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 10, weight: .semibold))
            streakText(streak)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(streak > 0 ? Theme.brass : .secondary)
        .lineLimit(1)
    }

    /// The streak in the kicker's trailing slot, in brass with its flame once there is one.
    private func streakBadge(_ streak: Int) -> Text {
        guard streak > 0 else { return streakText(streak) }
        return (Text(Image(systemName: "flame.fill")) + Text(" ") + streakText(streak))
            .foregroundStyle(Theme.brass)
    }

    private func streakText(_ streak: Int) -> Text {
        switch streak {
        case 0: Text("No streak yet")
        case 1: Text("1 day streak")
        default: Text("\(streak) day streak")
        }
    }
}

// MARK: - Button

/// One prayer, tappable once its time has come. Prayed fills the tile jade with a tick; a
/// prayer still ahead is drawn but inert, so the row keeps its shape through the day.
private struct LogButton: View {
    let prayer: Prayer
    let entry: SajadahEntry

    var body: some View {
        let state = entry.snapshot.state(for: prayer, at: entry.date)
        let loggable = entry.snapshot.isLoggable(prayer, at: entry.date)
        let dayKey = entry.snapshot.dayKey(for: entry.date)

        Button(intent: LogPrayerIntent(prayer: prayer, dayKey: dayKey)) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tileFill(state, loggable: loggable))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tileStroke(state, loggable: loggable), lineWidth: 1)
                    Image(systemName: state == .prayed ? "checkmark" : prayer.systemImage)
                        .font(.system(size: state == .prayed ? 13 : 14, weight: state == .prayed ? .bold : .medium))
                        .foregroundStyle(glyphColor(state, loggable: loggable))
                }
                .frame(width: 34, height: 30)

                Text(prayer.displayName)
                    .font(.system(size: 9, weight: state == .prayed ? .semibold : .regular))
                    .foregroundStyle(loggable ? .primary : Ink.onLattice.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!loggable)
        .accessibilityLabel(accessibilityLabel(state, loggable: loggable))
    }

    private func tileFill(_ state: PrayerLogState?, loggable: Bool) -> Color {
        switch state {
        case .prayed: Theme.jade
        case .missed: Color(nsColor: .systemRed).opacity(0.14)
        case nil: prayer.tint.opacity(loggable ? 0.14 : 0.06)
        }
    }

    private func tileStroke(_ state: PrayerLogState?, loggable: Bool) -> Color {
        switch state {
        case .prayed: .clear
        case .missed: Color(nsColor: .systemRed).opacity(0.3)
        case nil: prayer.tint.opacity(loggable ? 0.35 : 0.12)
        }
    }

    private func glyphColor(_ state: PrayerLogState?, loggable: Bool) -> Color {
        switch state {
        case .prayed: .white
        case .missed: Color(nsColor: .systemRed).opacity(0.8)
        case nil: prayer.tint.opacity(loggable ? 1 : 0.45)
        }
    }

    private func accessibilityLabel(_ state: PrayerLogState?, loggable: Bool) -> String {
        switch state {
        case .prayed: "\(prayer.displayName), prayed. Tap to clear."
        case .missed: "\(prayer.displayName), missed. Tap to mark prayed."
        case nil: loggable ? "\(prayer.displayName), not logged. Tap to mark prayed." : "\(prayer.displayName), not yet."
        }
    }
}
