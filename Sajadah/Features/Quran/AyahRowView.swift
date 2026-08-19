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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                AyahBadge(number: ayah.numberInSurah)

                Text(ayah.arabic)
                    .font(.arabic(arabicFont, size: arabicSize))
                    // Generous, but not arbitrary: Uthmani marks stack high above and below
                    // the baseline, and tighter leading makes them collide between lines.
                    .lineSpacing(arabicSize * 0.45)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)

                VStack(spacing: 6) {
                    Button(action: onToggleBookmark) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isBookmarked ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isBookmarked ? "Remove bookmark" : "Bookmark this ayah")

                    if ayah.hasSajda {
                        Image(systemName: "figure.mind.and.body")
                            .foregroundStyle(.secondary)
                            .help("Verse of prostration")
                    }
                }
                .font(.system(size: 12))
            }

            if !ayah.translation.isEmpty {
                Text(ayah.translation)
                    .font(.system(size: translationSize))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
    }
}

private struct AyahBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 24)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(.quaternary)
            }
    }
}
