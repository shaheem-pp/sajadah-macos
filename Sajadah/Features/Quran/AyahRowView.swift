//
//  AyahRowView.swift
//  Sajadah
//

import SwiftUI

/// One ayah: Arabic right-aligned, translation directly beneath.
///
/// Interleaved rather than in two columns, because ayah lengths vary enormously — Al-Baqara
/// 282 against Ar-Rahman's refrains — and columns would drift apart badly.
struct AyahRowView: View {
    let ayah: Ayah
    let arabicFont: String
    let arabicSize: Double
    let translationSize: Double
    let isBookmarked: Bool
    let isHighlighted: Bool
    let onToggleBookmark: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                // The rosette is how a printed mushaf numbers a verse, so it belongs here in
                // place of a UI badge.
                AyahRosette(number: ayah.numberInSurah, size: 26)
                    .padding(.top, 2)

                Text(ayah.arabic)
                    .font(.arabic(arabicFont, size: arabicSize))
                    // Generous, but not arbitrary: Uthmani marks stack high above and below
                    // the baseline, and tighter leading makes them collide between lines.
                    .lineSpacing(arabicSize * 0.45)
                    // `.leading` reads backwards here on purpose: the environment below
                    // makes this subtree right-to-left, so leading *is* the right edge.
                    // Asking for `.trailing` flushes Arabic to the left, which is wrong.
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)

                controls
            }

            if !ayah.translation.isEmpty {
                Text(ayah.translation)
                    .font(.system(size: translationSize))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    /// Bookmarks stay visible once set; the affordance only appears on hover, so a page of
    /// unbookmarked verses is a clean column of text.
    private var controls: some View {
        VStack(spacing: 7) {
            Button(action: onToggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Theme.jade : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isBookmarked || isHovering ? 1 : 0)
            .help(isBookmarked ? "Remove bookmark" : "Bookmark this ayah")

            if ayah.hasSajda {
                Image(systemName: "figure.mind.and.body")
                    .foregroundStyle(Theme.brass)
                    .help("Verse of prostration")
            }
        }
        .font(.system(size: 12))
        .frame(width: 14)
    }

    private var background: Color {
        if isHighlighted { return Theme.jade.opacity(0.11) }
        if isHovering { return Theme.wellFill }
        return .clear
    }
}
