//
//  NextPrayerHero.swift
//  Sajadah
//

import SwiftUI

/// The one thing the app exists to answer, for whichever part of the day it currently is:
/// how long until the Adhan, whether jamaah is still catchable, or how much of this prayer's
/// window is left. `init(phase:...)` words each of those; everything here just renders it.
///
/// The panel is washed in the light of that prayer's hour — pre-dawn indigo through to night
/// blue — so the answer is legible from across the room before a single word is read. The
/// lattice and the arch behind it are held near the floor of visibility on purpose; they are
/// there to give the surface a texture, not to be looked at.
///
/// It is as tall as its words and no taller. Everything behind them — the wash, the lattice —
/// would happily fill any height offered, and beside a taller column that is exactly what it
/// did: several hundred points of sky under four lines of text.
struct NextPrayerHero: View {
    /// Whose hour the panel is washed in. Not always the prayer being counted down to — a
    /// finished day sits in Isha's night whatever comes next.
    let prayer: Prayer
    /// The headline. Usually the prayer's name, but not for a day that is done.
    let title: String
    /// The big number, already a whole phrase: "in 6h 24m", "2h 53m left".
    let countdown: String
    /// The supporting clock time, already labelled where it needs to be. May be empty.
    let clock: String
    var place: String?
    var hijri: String?
    /// The day's fasting status, worn as a chip on the kicker row. The popover shows the label
    /// alone and keeps the reason for the tooltip; the window has room for both.
    var fasting: FastingBadge?
    var isStale: Bool = false
    /// How far the current window has run, 0...1. Nil when there is nothing to measure from.
    var progress: Double?
    var compact: Bool = false
    var kicker: String = "NEXT PRAYER"
    /// Draws a brighter edge on the panel. Reserved for the minutes before a jamaah, which is
    /// the only moment in the day where being late is a different outcome rather than a
    /// later one.
    var isUrgent: Bool = false

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ornament
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(isUrgent ? 0.55 : 0.10), lineWidth: isUrgent ? 1.6 : 1)
        }
        .animation(.snappy(duration: 0.25), value: isUrgent)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clock.isEmpty ? "\(title), \(countdown)" : "\(title), \(countdown), \(clock)")
    }

    // MARK: Layers

    private var background: some View {
        prayer.sky
            // Guarantees the text keeps its contrast wherever the gradient happens to be
            // light — the copy all sits in the leading half.
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.34), .black.opacity(0.02)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
    }

    private var ornament: some View {
        ZStack(alignment: .bottomTrailing) {
            StarLattice(spacing: compact ? 38 : 52, color: Theme.ornamentOnSky, lineWidth: 0.8)

            // A niche rising off the bottom edge, with the hour's symbol standing in it.
            // Anchored to that edge rather than centred, so the top-right corner stays clear
            // for the fasting chip.
            MihrabArch()
                .fill(.white.opacity(0.08))
                .overlay {
                    MihrabArch().stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .frame(width: compact ? 58 : 88, height: compact ? 76 : 118)
                .overlay {
                    Image(systemName: prayer.systemImage)
                        .font(.system(size: compact ? 18 : 27, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                        .offset(y: compact ? 8 : 12)
                }
                .offset(x: compact ? 4 : 6, y: compact ? 14 : 20)
        }
        .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            // The status row: what kind of moment this is, whether the times are current, and
            // whether today is a fast. The first two are pinned to one line — the chip is
            // the one that gives when the popover is short of room.
            HStack(spacing: 6) {
                Text(kicker)
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
                    .fixedSize()

                if isStale {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.system(size: compact ? 9 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                }

                if let fasting {
                    // A trailing frame rather than a Spacer before the chip: a Spacer is as
                    // flexible as the chip, so a short row was split between them and the
                    // chip truncated with room still to its left.
                    fastingChip(fasting)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 26 : 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(countdown)
                        .font(.system(size: compact ? 14 : 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))

                    // A finished day past the end of the cached timings has no clock time to
                    // show, and a lone separator would read as something failing to load.
                    if !clock.isEmpty {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.45))

                        Text(clock)
                            .font(.system(size: compact ? 13 : 16, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }

            if let progress {
                windowBar(progress)
            }

            if place != nil || hijri != nil {
                footer
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 13 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How much of the window between the last prayer and the next has run.
    private func windowBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.20))
                Capsule()
                    .fill(.white.opacity(0.80))
                    .frame(width: max(3, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .frame(maxWidth: compact ? .infinity : 320)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    /// Brass on the sky, as the footer used to write it, but in the corner rather than as a
    /// third item on the footer's one line — which, in the popover, it never fit on: the date
    /// and the fast truncated each other. The corner is the lightest part of the wash, so the
    /// chip carries its own scrim.
    private func fastingChip(_ badge: FastingBadge) -> some View {
        Button {
            navigation.settingsPane = .fasting
            openSettings()
        } label: {
            Text(compact ? badge.label : badge.text)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                .foregroundStyle(Theme.brassOnSky)
                .lineLimit(1)
                // "Fasting tomorrow" beside "AT THE MASJID" and "Offline" is the one row the
                // popover can't seat at full size; a fifth smaller is still legible, and
                // beats an ellipsis.
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.22), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.brassOnSky.opacity(0.35), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        // The popover's chip drops the reason, so the tooltip is where it went.
        .help(compact ? badge.text : "Adjust the Hijri date and fasting days")
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let place {
                Image(systemName: "location.fill")
                    .font(.system(size: compact ? 8 : 9))
                Text(place)
            }
            if place != nil && hijri != nil {
                separator
            }
            // The date is the thing you'd want to adjust, so it is also the way to where that
            // happens — the chip above is the only other cue in the app that it can be.
            if let hijri {
                Button {
                    navigation.settingsPane = .fasting
                    openSettings()
                } label: {
                    Text(hijri)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Adjust the Hijri date and fasting days")
            }
        }
        .font(.system(size: compact ? 10.5 : 12))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .padding(.top, compact ? 1 : 3)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.white.opacity(0.4))
    }
}

// MARK: - Wording each phase

extension NextPrayerHero {

    /// How close to a jamaah counts as "leave now" rather than "soon".
    private static let urgentLead: TimeInterval = 15 * 60

    /// Builds the panel from the day's phase. Every state is worded here and only here, so
    /// two places rendering the same moment can't describe it differently.
    ///
    /// Fails on `.unavailable`: with no timings there is no panel to draw, and an empty one
    /// would sit at the top of the window pretending otherwise.
    init?(
        phase: DayPhase,
        now: Date,
        use24Hour: Bool,
        timeZone: TimeZone,
        place: String?,
        hijri: String?,
        fasting: FastingBadge? = nil,
        isStale: Bool = false,
        compact: Bool = false
    ) {
        func at(_ date: Date) -> String {
            TimeFormatting.clock(date, use24Hour: use24Hour, timeZone: timeZone)
        }
        func left(until date: Date) -> String {
            TimeFormatting.countdown(date.timeIntervalSince(now))
        }

        switch phase {
        case .awaitingAdhan(let next):
            self.prayer = next.prayer
            self.kicker = "NEXT PRAYER"
            self.title = next.prayer.displayName
            self.countdown = "in \(left(until: next.date))"
            self.clock = at(next.date)
            // Nothing named to measure from between windows, so no bar rather than a bar
            // spanning a gap the user couldn't name.
            self.progress = nil
            self.isUrgent = false

        case .awaitingIqamah(let prayer, _, let iqamah):
            self.prayer = prayer
            self.kicker = "AT THE MASJID"
            self.title = "\(prayer.displayName) jamaah"
            self.countdown = "in \(left(until: iqamah))"
            self.clock = at(iqamah)
            self.progress = phase.progress(at: now)
            self.isUrgent = iqamah.timeIntervalSince(now) <= Self.urgentLead

        case .inWindow(let prayer, _, let closesAt):
            self.prayer = prayer
            self.kicker = "IN THE WINDOW"
            self.title = prayer.displayName
            self.countdown = "\(left(until: closesAt)) left"
            self.clock = "until \(at(closesAt))"
            self.progress = phase.progress(at: now)
            self.isUrgent = false

        case .dayComplete(let next):
            // The wash stays in Isha's night whatever comes next — the day being over is what
            // the panel is saying, not that Fajr is coming.
            self.prayer = .isha
            self.kicker = "DAY COMPLETE"
            self.title = "All five prayed"
            if let next {
                self.countdown = "\(next.prayer.displayName) in \(left(until: next.date))"
                self.clock = at(next.date)
            } else {
                self.countdown = "Tomorrow's times aren't loaded yet"
                self.clock = ""
            }
            self.progress = nil
            self.isUrgent = false

        case .unavailable:
            return nil
        }

        self.place = place
        self.hijri = hijri
        self.fasting = fasting
        self.isStale = isStale
        self.compact = compact
    }
}
