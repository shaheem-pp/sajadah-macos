//
//  WidgetChrome.swift
//  SajadahWidgets
//
//  The pieces every widget is built from, so six widgets read as one set: two backgrounds,
//  one kicker, one glyph tile, one way of drawing "how far through". Anything drawn here
//  answers to the app's Theme — a widget on the desktop and the popover in the menubar are
//  the same object seen from two places.
//

import SwiftUI
import WidgetKit

// MARK: - Family

/// Hands the widget family to a view as a plain value. Views take the family as a parameter
/// rather than reading the environment themselves, so they can be rendered outside WidgetKit
/// — the design was checked in a harness that draws them to PNG at each size.
struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

// MARK: - Backgrounds

/// The quiet surface: the system's own widget fill with the khatim lattice over it. For
/// widgets that are reference material — a table of times, a verse — rather than a moment.
struct LatticeBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            StarLattice(spacing: 34, lineWidth: 0.7)
        }
    }
}

/// The hour's light, as the app's hero draws it: the prayer's sky, a darkening towards the
/// text corner so white copy keeps its contrast, the lattice, and the mihrab niche rising off
/// the bottom edge with the hour's symbol standing in it. For widgets that are about *now*.
struct SkyBackground: View {
    let prayer: Prayer?
    /// The niche is the one piece of ornament a small widget has room for; a wider one can
    /// carry it larger without crowding the copy.
    var archWidth: CGFloat = 52
    var archOffset: CGSize = CGSize(width: 2, height: 14)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let prayer {
                prayer.sky
                LinearGradient(
                    colors: [.black.opacity(0.32), .black.opacity(0.02)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                StarLattice(spacing: 32, color: Theme.ornamentOnSky, lineWidth: 0.7)

                MihrabArch()
                    .fill(.white.opacity(0.08))
                    .overlay { MihrabArch().stroke(.white.opacity(0.14), lineWidth: 1) }
                    .frame(width: archWidth, height: archWidth * 1.32)
                    .overlay {
                        Image(systemName: prayer.systemImage)
                            .font(.system(size: archWidth * 0.33, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                            .offset(y: archWidth * 0.14)
                    }
                    .offset(archOffset)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
    }
}

// MARK: - Ink

/// Text colour on the two surfaces. On the sky everything is white at graded opacities; on
/// the lattice it is the system's own hierarchy, which follows light and dark mode itself.
enum Ink {
    case onSky, onLattice

    var primary: Color {
        switch self {
        case .onSky: .white
        case .onLattice: .primary
        }
    }

    var secondary: Color {
        switch self {
        case .onSky: .white.opacity(0.74)
        case .onLattice: .secondary
        }
    }

    var tertiary: Color {
        switch self {
        case .onSky: .white.opacity(0.50)
        case .onLattice: Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// The accent for earned or notable things — the brass, or its sky-safe variant.
    var brass: Color {
        switch self {
        case .onSky: Theme.brassOnSky
        case .onLattice: Theme.brass
        }
    }

    var jade: Color {
        switch self {
        case .onSky: .white
        case .onLattice: Theme.jade
        }
    }

    /// A rule or track — something meant to be seen second.
    var hairline: Color {
        switch self {
        case .onSky: .white.opacity(0.22)
        case .onLattice: .primary.opacity(0.10)
        }
    }
}

// MARK: - Kicker

/// The small-caps label at the top of every widget, with the Rub el Hizb leading it — the
/// same header the app's cards carry, so the widget is recognisably the same thing.
struct WidgetKicker: View {
    let title: String
    var trailing: Text? = nil
    var ink: Ink = .onLattice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            RubElHizb()
                .fill(ink == .onSky ? .white.opacity(0.55) : Theme.jade.opacity(0.55))
                .frame(width: 7, height: 7)
                .offset(y: -0.5)

            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let trailing {
                trailing
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Prayer glyph

/// A prayer's symbol in a small rounded tile, tinted with the light of its hour. The one
/// mark that lets a row, a strip and a button all be read as the same prayer.
struct PrayerGlyph: View {
    let prayer: Prayer
    var size: CGFloat = 16
    var ink: Ink = .onLattice
    /// The prayer in progress or up next — brighter, so the eye lands on it first.
    var emphasised: Bool = false
    /// A prayer whose time has gone recedes, unless it is the one being emphasised.
    var faded: Bool = false

    var body: some View {
        let tint = ink == .onSky ? Color.white : prayer.tint
        let fill = ink == .onSky
            ? Color.white.opacity(emphasised ? 0.26 : 0.12)
            : prayer.tint.opacity(emphasised ? 0.18 : 0.10)

        Image(systemName: prayer.systemImage)
            .font(.system(size: size * 0.56, weight: emphasised ? .semibold : .medium))
            .foregroundStyle(tint.opacity(faded && !emphasised ? 0.5 : 1))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(fill.opacity(faded && !emphasised ? 0.6 : 1))
            }
    }
}

// MARK: - Window bar

/// How far the current span has run — Adhan to Iqamah, or Adhan to the window's close.
struct WindowBar: View {
    let fraction: Double
    var ink: Ink = .onSky
    var height: CGFloat = 3
    /// Brass for the last minutes before a jamaah — the widget has no edge of its own to
    /// brighten the way the app's hero does.
    var urgent: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.hairline)
                Capsule()
                    .fill(urgent ? ink.brass : (ink == .onSky ? .white.opacity(0.85) : Theme.jade))
                    .frame(width: max(height, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Day strip

/// The five prayers as a row of glyphs on one rule — a timeline of the day. Prayed ones carry
/// a tick, the one in progress or up next is raised, and the rule fills up to it, so "where
/// am I in the day" is answered by shape before any time is read.
struct DayStrip: View {
    let snapshot: SajadahSnapshot
    let date: Date
    var ink: Ink = .onSky
    var glyphSize: CGFloat = 22
    var showsTimes: Bool = true

    var body: some View {
        let day = snapshot.today(at: date)
        let focus = snapshot.phase(at: date).prayer
        let prayers = DayLog.tracked
        let focusIndex = prayers.firstIndex { $0 == focus } ?? prayers.count

        VStack(spacing: 5) {
            ZStack(alignment: .leading) {
                // The rule, filled as far as the prayer in focus.
                GeometryReader { geometry in
                    let step = geometry.size.width / CGFloat(prayers.count)
                    let filled = step * (CGFloat(focusIndex) + 0.5)
                    Capsule()
                        .fill(ink.hairline)
                        .frame(height: 1.5)
                        .padding(.horizontal, step / 2)
                    Capsule()
                        .fill(ink == .onSky ? .white.opacity(0.7) : Theme.jade.opacity(0.7))
                        .frame(width: max(0, filled - step / 2), height: 1.5)
                        .padding(.leading, step / 2)
                }
                .frame(height: glyphSize)

                HStack(spacing: 0) {
                    ForEach(prayers, id: \.self) { prayer in
                        marker(prayer, isFocus: prayer == focus, hasPassed: day.map { $0.time(for: prayer) <= date } ?? false)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if showsTimes, let day {
                HStack(spacing: 0) {
                    ForEach(prayers, id: \.self) { prayer in
                        // The narrow "a"/"p": five times in a row is where "AM" stops being
                        // information, and a 24-hour locale is left exactly as it was.
                        Text(day.time(for: prayer), format: .dateTime.hour(.defaultDigits(amPM: .narrow)).minute())
                            .font(.system(size: 9.5, weight: prayer == focus ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(prayer == focus ? ink.primary : ink.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func marker(_ prayer: Prayer, isFocus: Bool, hasPassed: Bool) -> some View {
        let prayed = snapshot.state(for: prayer, at: date) == .prayed
        return ZStack(alignment: .topTrailing) {
            PrayerGlyph(prayer: prayer, size: glyphSize, ink: ink, emphasised: isFocus, faded: hasPassed && !prayed)
                .overlay {
                    if isFocus {
                        RoundedRectangle(cornerRadius: glyphSize * 0.28, style: .continuous)
                            .strokeBorder(ink == .onSky ? .white.opacity(0.9) : prayer.tint, lineWidth: 1.2)
                    }
                }
            if prayed {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(ink == .onSky ? prayer.tint : .white)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(ink == .onSky ? .white : Theme.jade))
                    .offset(x: 3, y: -3)
            }
        }
    }
}

// MARK: - Prayer ring

/// Five arcs on one ring, one per prayer in the order of the day: filled once prayed, hollow
/// while unanswered, dimmed red for a missed one. A day is complete when the ring closes.
struct PrayerRing: View {
    let snapshot: SajadahSnapshot
    let date: Date
    var size: CGFloat = 84
    var lineWidth: CGFloat = 7

    private static let gap: Double = 0.035

    var body: some View {
        let prayers = DayLog.tracked
        let span = 1.0 / Double(prayers.count)
        let focus = snapshot.phase(at: date).prayer

        ZStack {
            ForEach(Array(prayers.enumerated()), id: \.element) { index, prayer in
                let start = Double(index) * span + Self.gap / 2
                let end = Double(index + 1) * span - Self.gap / 2
                let state = snapshot.state(for: prayer, at: date)

                Circle()
                    .trim(from: start, to: end)
                    .stroke(arcColor(state, isFocus: prayer == focus), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func arcColor(_ state: PrayerLogState?, isFocus: Bool) -> Color {
        switch state {
        case .prayed: Theme.jade
        case .missed: Color(nsColor: .systemRed).opacity(0.45)
        case nil: isFocus ? Theme.jade.opacity(0.32) : Color.primary.opacity(0.10)
        }
    }
}

// MARK: - Empty state

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

// MARK: - Live countdown

/// The ticking figure, in the widget's own idiom: a timer face rather than the app's "6h 24m"
/// prose, because a widget can't re-render each minute and `Text(timerInterval:)` counts on
/// its own. Guards the range — a target at or before `from` would trap.
struct Countdown: View {
    let from: Date
    let to: Date
    var size: CGFloat = 30
    var weight: Font.Weight = .semibold
    var ink: Ink = .onSky

    var body: some View {
        Group {
            if to > from {
                Text(timerInterval: from...to, countsDown: true, showsHours: true)
            } else {
                Text("now")
            }
        }
        .font(.system(size: size, weight: weight, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(ink.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
