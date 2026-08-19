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
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(day.events) { event in
                PrayerRow(
                    event: event,
                    isHighlighted: event.prayer == highlighted,
                    hasPassed: passedBefore.map { event.date < $0 } ?? false,
                    use24Hour: use24Hour,
                    timeZone: day.timeZone,
                    logging: logging,
                    compact: compact
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
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 9 : 11) {
            glyph

            Text(event.prayer.displayName)
                .font(.system(size: compact ? 13 : 14, weight: isHighlighted ? .semibold : .regular))
                .foregroundStyle(foreground)

            Spacer(minLength: 12)

            Text(TimeFormatting.clock(event.date, use24Hour: use24Hour, timeZone: timeZone))
                .font(.system(size: compact ? 13 : 14, weight: isHighlighted ? .semibold : .regular))
                .monospacedDigit()
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
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, compact ? 8 : 12)
        .padding(.vertical, compact ? 5 : 7)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(event.prayer.tint.opacity(0.14))
            }
        }
        // A rule down the leading edge marks the row without the fill having to be heavy
        // enough to notice on its own.
        .overlay(alignment: .leading) {
            if isHighlighted {
                Capsule()
                    .fill(event.prayer.tint)
                    .frame(width: 2.5)
                    .padding(.vertical, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
    }

    /// The hour's own symbol, in the hour's own colour. Sunrise stays grey — it closes the
    /// Fajr window rather than being a prayer, so it never competes for attention.
    private var glyph: some View {
        Image(systemName: event.prayer.systemImage)
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(glyphTint)
            .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(glyphTint.opacity(isHighlighted ? 0.16 : 0.09))
            }
    }

    private var glyphTint: Color {
        guard event.prayer.isPrayer else { return .secondary }
        return hasPassed && !isHighlighted ? event.prayer.tint.opacity(0.55) : event.prayer.tint
    }

    private var foreground: Color {
        if isHighlighted { return .primary }
        if hasPassed || !event.prayer.isPrayer { return .secondary }
        return .primary
    }
}

// MARK: - Log button

private struct LogButton: View {
    let state: PrayerLogState?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .prayed:
                    Circle().fill(Theme.jade)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)

                case .missed:
                    Circle().fill(Color.orange.opacity(0.18))
                    Circle().strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)

                case nil:
                    Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.2)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.25)
        .animation(.snappy(duration: 0.18), value: state)
        .help(helpText)
    }

    private var helpText: String {
        switch state {
        case .prayed: "Prayed — click to mark missed"
        case .missed: "Missed — click to clear"
        case nil: "Click to mark as prayed"
        }
    }
}
