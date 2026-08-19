//
//  AyahOfTheDayView.swift
//  Sajadah
//

import SwiftUI

/// The verse of the day, sized for the menubar popover. Clicking it opens the reader there.
struct AyahOfTheDayView: View {
    let ayah: DailyAyah
    let arabicFont: String
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    RubElHizb()
                        .fill(Theme.jade.opacity(0.5))
                        .frame(width: 7, height: 7)

                    Text("AYAH OF THE DAY")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    Text("\(ayah.surahEnglishName) \(ayah.ref.surah):\(ayah.ref.ayah)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Text(ayah.arabic)
                    .font(.arabic(arabicFont, size: 17))
                    .lineSpacing(9)
                    // `.leading` reads backwards here on purpose: the environment below
                    // makes this subtree right-to-left, so leading *is* the right edge.
                    // Asking for `.trailing` flushes Arabic to the left, which is wrong.
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(3)

                Text(ayah.translation)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(isHovering ? Theme.jade.opacity(0.07) : Theme.wellFill)
            }
            // The lattice sits behind the verse rather than beside it, clipped to the well so
            // the panel reads as a single surface.
            .background {
                StarLattice(spacing: 34, lineWidth: 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                    .opacity(0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Open this ayah in the reader")
    }
}
