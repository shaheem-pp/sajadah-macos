//
//  PrayerListView.swift
//  Sajadah
//

import SwiftUI

/// Wiring for the tap-to-log control on each row. Optional, so the week-ahead table can reuse
/// the same list without offering to log a prayer three days from now.
struct PrayerLogging {
    let state: (Prayer) -> PrayerLogState?
    let cycle: (Prayer) -> Void
}

/// One day's timings as rows. Shared by the menubar popover and the main window so the two
/// can't drift apart.
struct PrayerListView: View {
    let day: DayTimings
    /// The prayer to call out — normally the next one up.
    var highlighted: Prayer?
    /// Timings before this instant are dimmed as "already passed".
    var passedBefore: Date?
    var use24Hour: Bool = false
    var logging: PrayerLogging?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(day.events) { event in
                PrayerRow(
                    event: event,
                    isHighlighted: event.prayer == highlighted,
                    hasPassed: passedBefore.map { event.date < $0 } ?? false,
                    use24Hour: use24Hour,
                    timeZone: day.timeZone,
                    logging: logging
                )
            }
        }
    }
}

private struct PrayerRow: View {
    let event: PrayerEvent
    let isHighlighted: Bool
    let hasPassed: Bool
    let use24Hour: Bool
    let timeZone: TimeZone
    let logging: PrayerLogging?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.prayer.systemImage)
                .frame(width: 16)
                .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)

            Text(event.prayer.displayName)
                .fontWeight(isHighlighted ? .semibold : .regular)

            Spacer(minLength: 12)

            Text(TimeFormatting.clock(event.date, use24Hour: use24Hour, timeZone: timeZone))
                .monospacedDigit()
                .fontWeight(isHighlighted ? .semibold : .regular)
                .foregroundStyle(foreground)

            if let logging, event.prayer.isPrayer {
                LogButton(
                    state: logging.state(event.prayer),
                    // A prayer can only be logged once its time has actually come.
                    isEnabled: hasPassed,
                    action: { logging.cycle(event.prayer) }
                )
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
    }

    private var foreground: Color {
        if isHighlighted { return .primary }
        // Sunrise is context rather than a prayer, so it never competes for attention.
        if hasPassed || !event.prayer.isPrayer { return .secondary }
        return .primary
    }
}

private struct LogButton: View {
    let state: PrayerLogState?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state?.systemImage ?? "circle")
                .font(.system(size: 13))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.25)
        .help(helpText)
    }

    private var tint: Color {
        switch state {
        case .prayed: .green
        case .missed: .orange
        case nil: .secondary
        }
    }

    private var helpText: String {
        switch state {
        case .prayed: "Prayed — click to mark missed"
        case .missed: "Missed — click to clear"
        case nil: "Click to mark as prayed"
        }
    }
}
