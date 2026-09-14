//
//  AyahWidget.swift
//  SajadahWidgets
//

import SwiftUI
import WidgetKit

/// A verse each day, set the way a mushaf sets one: the Arabic first and largest, the
/// translation beneath it. Medium keeps the verse to the right where Arabic starts; large
/// centres it like a page and gives it the room to be read rather than glanced at.
struct AyahWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AyahOfTheDay", provider: SajadahProvider()) { entry in
            FamilyReader { family in
                AyahView(entry: entry, family: family)
            }
            .widgetTimeZone(entry.snapshot)
            .containerBackground(for: .widget) { LatticeBackground() }
        }
        .configurationDisplayName("Ayah of the Day")
        .description("A verse each day, with its translation. Opens the surah in Sajadah.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct AyahView: View {
    let entry: SajadahEntry
    let family: WidgetFamily

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        if let ayah = entry.snapshot.dailyAyah {
            VStack(alignment: .leading, spacing: 0) {
                WidgetKicker(
                    title: "Ayah of the day",
                    trailing: Text("\(ayah.surahEnglishName) \(ayah.ref.surah):\(ayah.ref.ayah)")
                )

                // Equal spacers above and below centre the verse in whatever room is left,
                // while the label stays pinned at the top.
                Spacer(minLength: 0)

                VStack(alignment: isLarge ? .center : .leading, spacing: isLarge ? 14 : 8) {
                    Text(ayah.arabic)
                        .font(.arabic(ArabicFontChoice.defaultID, size: isLarge ? 25 : 18))
                        .lineSpacing(isLarge ? 13 : 7)
                        // `.leading` is the right edge inside the right-to-left environment
                        // below; asking for `.trailing` flushes Arabic to the left.
                        .multilineTextAlignment(isLarge ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: isLarge ? .center : .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineLimit(isLarge ? 6 : 3)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, isLarge ? 6 : 0)

                    if isLarge {
                        OrnamentDivider()
                            .frame(maxWidth: 160)
                    }

                    Text(ayah.translation)
                        .font(.system(size: isLarge ? 12.5 : 11))
                        .lineSpacing(isLarge ? 3 : 1)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(isLarge ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: isLarge ? .center : .leading)
                        .lineLimit(isLarge ? 7 : 3)
                        .padding(.horizontal, isLarge ? 10 : 0)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(SajadahLink.ayah(ayah.ref))
        } else {
            WidgetEmptyView(message: "Open Sajadah to load the Quran.")
                .widgetURL(SajadahLink.today)
        }
    }
}
