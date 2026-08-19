//
//  Theme.swift
//  Sajadah
//

import AppKit
import SwiftUI

// MARK: - Dynamic colours

/// Builds a colour that resolves itself against the current appearance.
///
/// `nonisolated` because AppKit calls the provider closure while resolving, off the main
/// actor; the `Color` that comes back is `Sendable` either way.
nonisolated func adaptiveColor(light: UInt32, dark: UInt32, opacity: Double = 1) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: opacity
        )
    })
}

// MARK: - Palette

/// The app's visual vocabulary in one place.
///
/// Two colours carry the identity — a deep jade and a warm brass, both long-standing in
/// Islamic art — kept desaturated so they read as a wash over macOS's own materials rather
/// than as chrome painted on top of them.
enum Theme {

    // Identity

    /// The app tint. Darkened in light mode so it still carries text against white.
    static let jade = adaptiveColor(light: 0x0B6E4F, dark: 0x4FCBA0)
    /// Reserved for earned things — streaks, records, ornament.
    static let brass = adaptiveColor(light: 0xA0742A, dark: 0xDFB55F)

    // Surfaces

    static let cardFill = adaptiveColor(light: 0xFFFFFF, dark: 0x1C2024)
    static let cardStroke = adaptiveColor(light: 0x101820, dark: 0xFFFFFF, opacity: 0.08)
    static let hairline = adaptiveColor(light: 0x101820, dark: 0xFFFFFF, opacity: 0.07)
    static let wellFill = adaptiveColor(light: 0x101820, dark: 0xFFFFFF, opacity: 0.035)

    // Ornament

    /// Pattern work never competes with content, so it sits near the floor of visibility.
    static let ornament = adaptiveColor(light: 0x0B6E4F, dark: 0xFFFFFF, opacity: 0.06)
    /// The same lattice over a saturated hero needs to be light-on-dark instead.
    static let ornamentOnSky = adaptiveColor(light: 0xFFFFFF, dark: 0xFFFFFF, opacity: 0.14)

    // Metrics

    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 9
}

// MARK: - Time of day

/// Each prayer carries the light of its hour. The gradients are deliberately low-chroma —
/// enough to tell dawn from dusk at a glance, not enough to fight the text sitting on them.
extension Prayer {

    /// The single colour that stands for this prayer in rows, glyphs and badges.
    var tint: Color {
        switch self {
        case .fajr: adaptiveColor(light: 0x4A5585, dark: 0x8E9AD0)
        case .sunrise: adaptiveColor(light: 0xB07A45, dark: 0xE0AE79)
        case .dhuhr: adaptiveColor(light: 0x2E7FA8, dark: 0x76BEDE)
        case .asr: adaptiveColor(light: 0xA8762F, dark: 0xE0B269)
        case .maghrib: adaptiveColor(light: 0xA4553F, dark: 0xE09070)
        case .isha: adaptiveColor(light: 0x3A4674, dark: 0x8792C6)
        }
    }

    /// Two stops for the hero wash, darkest first.
    var skyColors: [Color] {
        switch self {
        case .fajr:
            [adaptiveColor(light: 0x2C3663, dark: 0x1B2140),
             adaptiveColor(light: 0x7A6C93, dark: 0x453A5E)]
        case .sunrise:
            [adaptiveColor(light: 0xA96637, dark: 0x6B3F22),
             adaptiveColor(light: 0xCE9455, dark: 0x8F6535)]
        case .dhuhr:
            [adaptiveColor(light: 0x2A6E96, dark: 0x143A52),
             adaptiveColor(light: 0x6FA8C6, dark: 0x2E5F7D)]
        case .asr:
            [adaptiveColor(light: 0x8E6026, dark: 0x5A3D18),
             adaptiveColor(light: 0xC2914C, dark: 0x876031)]
        case .maghrib:
            [adaptiveColor(light: 0x8E4536, dark: 0x54241B),
             adaptiveColor(light: 0xC97C57, dark: 0x8A4B33)]
        case .isha:
            [adaptiveColor(light: 0x232E55, dark: 0x141A33),
             adaptiveColor(light: 0x4C5885, dark: 0x2C3557)]
        }
    }

    var sky: LinearGradient {
        LinearGradient(colors: skyColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Card

extension View {
    /// The standard panel: a quiet fill, a hairline edge, no shadow. Cards group content
    /// without stacking visual weight the way `GroupBox` chrome does.
    func sajadahCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            }
    }
}

// MARK: - Section header

/// A titled band above a card. The star is the Rub el Hizb, the same mark that divides the
/// Quran into eighths — small enough here to read as punctuation rather than decoration.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            RubElHizb()
                .fill(Theme.jade.opacity(0.5))
                .frame(width: 7, height: 7)
                .offset(y: -1)

            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 2)
    }
}
