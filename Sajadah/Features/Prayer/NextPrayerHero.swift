//
//  NextPrayerHero.swift
//  Sajadah
//

import SwiftUI

/// The one thing the app exists to answer: which prayer is next, and how long is left.
///
/// The panel is washed in the light of that prayer's hour — pre-dawn indigo through to night
/// blue — so the answer is legible from across the room before a single word is read. The
/// lattice and the arch behind it are held near the floor of visibility on purpose; they are
/// there to give the surface a texture, not to be looked at.
struct NextPrayerHero: View {
    let prayer: Prayer
    let countdown: String
    let clock: String
    var place: String?
    var hijri: String?
    var isStale: Bool = false
    /// How far the current window has run, 0...1. Nil when there is nothing to measure from.
    var progress: Double?
    var compact: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            ornament
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : Theme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.displayName) in \(countdown), at \(clock)")
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
        ZStack(alignment: .trailing) {
            StarLattice(spacing: compact ? 38 : 52, color: Theme.ornamentOnSky, lineWidth: 0.8)

            // A niche rising off the bottom edge, with the hour's symbol standing in it.
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
            HStack(spacing: 6) {
                Text("NEXT PRAYER")
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.70))

                if isStale {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.system(size: compact ? 9 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .labelStyle(.titleAndIcon)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(prayer.displayName)
                    .font(.system(size: compact ? 26 : 38, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("in \(countdown)")
                        .font(.system(size: compact ? 14 : 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))

                    Text("·")
                        .foregroundStyle(.white.opacity(0.45))

                    Text(clock)
                        .font(.system(size: compact ? 13 : 16, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
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

    private var footer: some View {
        HStack(spacing: 5) {
            if let place {
                Image(systemName: "location.fill")
                    .font(.system(size: compact ? 8 : 9))
                Text(place)
            }
            if place != nil && hijri != nil {
                Text("·").foregroundStyle(.white.opacity(0.4))
            }
            if let hijri {
                Text(hijri)
            }
        }
        .font(.system(size: compact ? 10.5 : 12))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .padding(.top, compact ? 1 : 3)
    }
}
