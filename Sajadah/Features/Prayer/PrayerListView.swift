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
///
/// With `iqamah` supplied the list grows a second time column and a heading row: Adhan and
/// jamaah are the same five prayers, and reading one against the other is the whole question
/// ("how long until I have to leave"), which two separate cards made into arithmetic.
struct PrayerListView: View {
    let day: DayTimings
    /// The prayer to call out — normally the next one up.
    var highlighted: Prayer?
    /// Timings before this instant are dimmed as "already passed".
    var passedBefore: Date?
    var use24Hour: Bool = false
    /// The masjid's posted congregation times, when one is configured. Nil keeps the list
    /// single-column, which is what the popover wants at 300pt wide.
    var iqamah: IqamahTimes?
    /// Where those times came from, captioned under the Jamaah heading — a masjid host, so
    /// the column says whose times these are without a card of its own to say it in.
    var iqamahSource: String?
    var logging: PrayerLogging?
    var compact: Bool = false

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings

    private var showsIqamah: Bool { iqamah != nil }

    var body: some View {
        VStack(spacing: 2) {
            if showsIqamah {
                header
            }

            ForEach(day.events) { event in
                PrayerRow(
                    event: event,
                    isHighlighted: event.prayer == highlighted,
                    hasPassed: passedBefore.map { event.date < $0 } ?? false,
                    use24Hour: use24Hour,
                    timeZone: day.timeZone,
                    // Only sunrise has no congregation, and it reads better as an empty cell
                    // than as a dash — nothing is missing, there is simply nothing to hold.
                    iqamahValue: iqamah?.time(for: event.prayer),
                    showsIqamahColumn: showsIqamah,
                    logging: logging,
                    compact: compact
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: compact ? 9 : 11) {
            Color.clear
                .frame(width: compact ? 20 : 22, height: 1)

            Spacer(minLength: 12)

            Text("Adhan")
                .frame(width: PrayerColumn.adhan, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Jamaah")
                if let iqamahSource {
                    // The caption is also the way back to where these times are configured.
                    // A column that says whose times it holds is the natural place to look
                    // when you want to change whose times it holds.
                    Button {
                        navigation.settingsPane = .masjid
                        openSettings()
                    } label: {
                        Text(iqamahSource)
                            .font(.system(size: 9))
                            .textCase(nil)
                            .tracking(0)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("Change where jamaah times come from")
                }
            }
            .frame(width: PrayerColumn.iqamah, alignment: .trailing)

            if logging != nil {
                Color.clear.frame(width: PrayerColumn.log(compact: compact), height: 1)
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(0.7)
        .textCase(.uppercase)
        .foregroundStyle(.tertiary)
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, compact ? 8 : 12)
        .padding(.top, 3)
        .padding(.bottom, 4)
    }
}

/// Fixed widths so the two time columns and the heading above them stay in line. Only applied
/// when there are two columns to align — a single-column list keeps its natural layout.
private enum PrayerColumn {
    static let adhan: CGFloat = 76
    static let iqamah: CGFloat = 84
    /// Follows `LogButton`'s size, so the heading and the sunrise row hold the same width.
    static func log(compact: Bool) -> CGFloat { compact ? 16 : 18 }
}

private struct PrayerRow: View {
    let event: PrayerEvent
    let isHighlighted: Bool
    let hasPassed: Bool
    let use24Hour: Bool
    let timeZone: TimeZone
    let iqamahValue: String?
    let showsIqamahColumn: Bool
    let logging: PrayerLogging?
    let compact: Bool

    @State private var isHovering = false

    /// Only the window's rows light up under the pointer: they are the ones with a control
    /// to press, and the popover's are already dense enough without a second highlight.
    private var isHoverable: Bool { logging != nil && !compact }

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
                .frame(width: showsIqamahColumn ? PrayerColumn.adhan : nil, alignment: .trailing)

            if showsIqamahColumn {
                // Posted verbatim: these are strings off a masjid's own page, not times
                // Sajadah computed, and some of them are words ("Sunset") rather than clocks.
                // Sat beside the Adhan they finally mean something without being rewritten.
                Text(iqamahValue ?? "")
                    .font(.system(size: compact ? 13 : 14, weight: isHighlighted ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(iqamahForeground)
                    .lineLimit(1)
                    .frame(width: PrayerColumn.iqamah, alignment: .trailing)
            }

            if logging != nil {
                if event.prayer.isPrayer, let logging {
                    LogButton(
                        state: logging.state(event.prayer),
                        // A prayer can only be logged once its time has actually come.
                        isEnabled: hasPassed,
                        action: { logging.cycle(event.prayer) },
                        size: PrayerColumn.log(compact: compact)
                    )
                } else {
                    // Sunrise is never logged, but it still has to hold the column open or
                    // its times sit further right than everything above and below them.
                    Color.clear.frame(width: PrayerColumn.log(compact: compact), height: PrayerColumn.log(compact: compact))
                }
            }
        }
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, compact ? 8 : 12)
        .padding(.vertical, compact ? 5 : 7)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(event.prayer.tint.opacity(0.14))
            } else if isHovering {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(Theme.wellFill)
            }
        }
        .onHover { hovering in
            guard isHoverable else { return }
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
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

    /// The jamaah time is the actionable one, so it holds its weight a step longer than the
    /// Adhan beside it — but a passed row still settles back with the rest.
    private var iqamahForeground: Color {
        if isHighlighted { return .primary }
        return hasPassed ? .secondary : .primary
    }
}
