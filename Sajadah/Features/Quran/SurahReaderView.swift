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
                        basmala
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
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 20)
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

    // MARK: Header

    /// The surah opens under a mihrab — the niche a mosque points towards — carrying the
    /// surah's number, with the Arabic title set large underneath.
    ///
    /// The title sits below the arch rather than inside it because surah names run from
    /// "طه" to "ٱلْمُطَفِّفِينَ"; fitting the longest of them inside a niche would mean
    /// squashing the arch flat, and a flattened mihrab stops reading as one.
    private func header(_ text: SurahText) -> some View {
        VStack(spacing: 12) {
            ZStack {
                MihrabArch()
                    .fill(Theme.jade.opacity(0.06))
                MihrabArch()
                    .stroke(Theme.jade.opacity(0.28), lineWidth: 1)
                MihrabArch()
                    .inset(by: 4)
                    .stroke(Theme.jade.opacity(0.14), lineWidth: 0.75)

                Text("\(text.surah.number)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.jade)
                    .padding(.top, 16)
            }
            .frame(width: 54, height: 68)

            Text(text.surah.name)
                .font(.arabic(settings.arabicFontName, size: settings.arabicFontSize * 1.2))
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.center)

            HStack(spacing: 7) {
                Text(text.surah.englishName)
                    .fontWeight(.semibold)
                Text("·")
                Text(text.surah.englishNameTranslation)
                Text("·")
                Text("\(text.surah.numberOfAyahs) ayahs")
                Text("·")
                Text(text.surah.revelationType)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .padding(.horizontal, 12)
    }

    private var basmala: some View {
        VStack(spacing: 14) {
            OrnamentDivider()
                .frame(maxWidth: 300)

            Text(QuranText.basmala)
                .font(.arabic(settings.arabicFontName, size: settings.arabicFontSize))
                .environment(\.layoutDirection, .rightToLeft)

            OrnamentDivider()
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
