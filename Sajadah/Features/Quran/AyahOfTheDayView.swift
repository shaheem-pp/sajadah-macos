//
//  AyahOfTheDayView.swift
//  Sajadah
//

import SwiftUI

/// The verse of the day. Clicking it opens the reader at that ayah.
struct AyahOfTheDayView: View {
    /// `.tile` is a self-contained well with its own heading, sized for the popover. `.card`
    /// is the verse alone at reading size, for a page that already labels the section and
    /// supplies the surface — a tile nested in a card would say "Ayah of the day" twice.
    enum Style {
        case tile
        case card
    }

    let ayah: DailyAyah
    let arabicFont: String
    var style: Style = .tile
    let onOpen: () -> Void

    @State private var isHovering = false

    private var isTile: Bool { style == .tile }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: isTile ? 7 : 10) {
                if isTile {
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
                }

                Text(ayah.arabic)
                    .font(.arabic(arabicFont, size: isTile ? 17 : 22))
                    .lineSpacing(isTile ? 9 : 12)
                    // `.leading` reads backwards here on purpose: the environment below
                    // makes this subtree right-to-left, so leading *is* the right edge.
                    // Asking for `.trailing` flushes Arabic to the left, which is wrong.
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(isTile ? 3 : 4)

                Text(ayah.translation)
                    .font(.system(size: isTile ? 11.5 : 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(isTile ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(isTile ? 10 : 2)
            .background {
                if isTile {
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(isHovering ? Theme.jade.opacity(0.07) : Theme.wellFill)
                }
            }
            // The lattice sits behind the verse rather than beside it, clipped to the well so
            // the panel reads as a single surface.
            .background {
                if isTile {
                    StarLattice(spacing: 34, lineWidth: 0.7)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                        .opacity(0.7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(isTile ? .default : .link)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Open this ayah in the reader")
    }
}
