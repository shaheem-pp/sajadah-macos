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

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Ayah of the day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ayah.surahEnglishName) \(ayah.ref.surah):\(ayah.ref.ayah)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(ayah.arabic)
                    .font(.arabic(arabicFont, size: 17))
                    .lineSpacing(9)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(3)

                Text(ayah.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this ayah in the reader")
    }
}
