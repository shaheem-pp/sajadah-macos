//
//  Quran.swift
//  Sajadah
//

import Foundation

// MARK: - Surah

nonisolated struct Surah: Codable, Identifiable, Hashable, Sendable {
    let number: Int
    /// Arabic name, e.g. سُورَةُ ٱلْفَاتِحَةِ
    let name: String
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String

    var id: Int { number }

    /// Matches a sidebar filter against the number or either name.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if String(number) == query { return true }
        return englishName.localizedCaseInsensitiveContains(query)
            || englishNameTranslation.localizedCaseInsensitiveContains(query)
            || name.contains(query)
    }
}

// MARK: - Ayah

nonisolated struct Ayah: Codable, Identifiable, Hashable, Sendable {
    let numberInSurah: Int
    /// 1...6236 across the whole Quran.
    let numberInQuran: Int
    let arabic: String
    let translation: String
    let juz: Int
    let page: Int
    let hasSajda: Bool

    var id: Int { numberInQuran }
}

/// A surah with its text, in the cache's own shape rather than the API's.
nonisolated struct SurahText: Codable, Identifiable, Sendable {
    let surah: Surah
    let ayahs: [Ayah]
    /// Whether the Basmala belongs above ayah 1 as a header. False for Al-Fatiha (where it
    /// *is* ayah 1) and At-Tawba (which has none).
    let hasBasmala: Bool
    /// Which translation this text was fetched with — cached files are invalid if the user
    /// switches edition.
    let translationEdition: String

    var id: Int { surah.number }
}

// MARK: - Addressing

/// Points at one ayah. Used by bookmarks, resume, search results and deep links.
nonisolated struct AyahRef: Codable, Hashable, Sendable, Identifiable {
    let surah: Int
    let ayah: Int

    var id: String { "\(surah):\(ayah)" }
}

/// A single ayah lifted out of context, for the popover's verse of the day.
nonisolated struct DailyAyah: Codable, Sendable, Equatable {
    let ref: AyahRef
    let surahEnglishName: String
    let arabic: String
    let translation: String
}

// MARK: - Search

nonisolated struct QuranSearchMatch: Identifiable, Sendable, Hashable {
    let ref: AyahRef
    let surahEnglishName: String
    let text: String

    var id: String { ref.id }
}

// MARK: - Arabic Fonts

/// Fonts offered for the Quranic text.
///
/// Amiri Quran ships with the app and leads, because it is the only one here actually designed
/// for Uthmani orthography — see `BundledFonts` for what the others get wrong. The macOS faces
/// remain available as a matter of taste. Waseem is deliberately absent: its shaping of
/// Uthmani text is broken outright.
nonisolated struct ArabicFontChoice: Identifiable, Hashable, Sendable {
    /// Empty means the system Arabic face (SF Arabic).
    let id: String
    let name: String
    /// True for the bundled Quranic face, so the picker can mark it as the recommended one.
    var isQuranic = false

    static let system = ""
    static let defaultID = "Amiri Quran"

    static let all: [ArabicFontChoice] = [
        ArabicFontChoice(id: "Amiri Quran", name: "Amiri Quran", isQuranic: true),
        ArabicFontChoice(id: "Geeza Pro", name: "Geeza Pro"),
        ArabicFontChoice(id: system, name: "System (SF Arabic)"),
        ArabicFontChoice(id: "Al Bayan", name: "Al Bayan"),
        ArabicFontChoice(id: "Al Nile", name: "Al Nile"),
        ArabicFontChoice(id: "Baghdad", name: "Baghdad"),
        ArabicFontChoice(id: "Damascus", name: "Damascus"),
        ArabicFontChoice(id: "Mishafi", name: "Mishafi"),
    ]
}

// MARK: - Text Normalisation

/// The `quran-uthmani` edition needs cleaning before it can sit alongside a translation.
nonisolated enum QuranText {
    /// The Basmala exactly as the Uthmani edition writes it.
    static let basmala = "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ"

    /// Surah 1 has the Basmala as a genuine ayah; surah 9 has none. Every other surah gets it
    /// prepended to ayah 1 by the API, and must have it removed or the Arabic will not line up
    /// with a translation that never included it.
    static func expectsBasmalaHeader(surah: Int) -> Bool {
        surah != 1 && surah != 9
    }

    /// Strips the byte-order mark the API leaves on some verses, plus surrounding whitespace.
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes a leading Basmala from the given text, reporting whether one was there.
    static func strippingBasmala(from text: String) -> (text: String, removed: Bool) {
        let cleaned = clean(text)
        guard cleaned.hasPrefix(basmala) else { return (cleaned, false) }

        let remainder = clean(String(cleaned.dropFirst(basmala.count)))
        // A surah whose entire first ayah is the Basmala (Al-Fatiha) must keep it.
        guard !remainder.isEmpty else { return (cleaned, false) }
        return (remainder, true)
    }
}
