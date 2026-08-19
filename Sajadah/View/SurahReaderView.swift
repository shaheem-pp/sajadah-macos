//
//  SurahReaderView.swift
//  Sajadah
//

import SwiftUI

struct SurahReaderView: View {
    let surahNumber: Int
    /// Set to scroll to a particular ayah — from a search hit, a bookmark, or resume.
    var scrollTarget: Int?

    @Environment(QuranStore.self) private var quran
    @Environment(ReadingProgressStore.self) private var reading
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if let text = quran.text(for: surahNumber) {
                reader(text)
            } else {
                switch quran.state(for: surahNumber) {
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t load this surah", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { quran.loadSurah(surahNumber) }
                    }
                default:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: surahNumber) { quran.loadSurah(surahNumber) }
        .task(id: settings.translationEdition) { quran.loadSurah(surahNumber) }
    }

    private func reader(_ text: SurahText) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    header(text)

                    if text.hasBasmala {
                        Text(QuranText.basmala)
                            .font(.arabic(settings.arabicFontName, size: settings.arabicFontSize))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                    }

                    ForEach(text.ayahs) { ayah in
                        let ref = AyahRef(surah: surahNumber, ayah: ayah.numberInSurah)
                        AyahRowView(
                            ayah: ayah,
                            arabicFont: settings.arabicFontName,
                            arabicSize: settings.arabicFontSize,
                            translationSize: settings.translationFontSize,
                            isBookmarked: reading.isBookmarked(ref),
                            isHighlighted: scrollTarget == ayah.numberInSurah,
                            onToggleBookmark: { reading.toggleBookmark(ref) }
                        )
                        .id(ayah.numberInSurah)
                        .onAppear {
                            // Whatever is on screen is where you are; coalesced before it
                            // reaches disk.
                            reading.recordPosition(ref)
                        }

                        if ayah.numberInSurah != text.ayahs.last?.numberInSurah {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onAppear { jump(proxy) }
            .onChange(of: scrollTarget) { jump(proxy) }
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        guard let scrollTarget else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(scrollTarget, anchor: .center) }
        }
    }

    private func header(_ text: SurahText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text.surah.name)
                .font(.arabic(settings.arabicFontName, size: settings.arabicFontSize * 1.15))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                Text("\(text.surah.number). \(text.surah.englishName)")
                    .fontWeight(.semibold)
                Text("·")
                Text(text.surah.englishNameTranslation)
                Text("·")
                Text("\(text.surah.numberOfAyahs) ayahs")
                Text("·")
                Text(text.surah.revelationType)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
    }
}
