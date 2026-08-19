//
//  QuranAPI.swift
//  Sajadah
//

import Foundation

// MARK: - Errors

nonisolated enum QuranError: LocalizedError, Equatable {
    case badURL
    case offline
    case network(String)
    case badStatus(Int)
    case decoding(String)
    case missingEdition

    var errorDescription: String? {
        switch self {
        case .badURL:
            "Couldn’t build the request URL."
        case .offline:
            "No internet connection."
        case .network(let detail):
            detail
        case .badStatus(let code):
            "The Quran service returned an error (HTTP \(code))."
        case .decoding(let detail):
            "Couldn’t read the Quran service response. \(detail)"
        case .missingEdition:
            "The response didn’t include both the Arabic text and the translation."
        }
    }
}

// MARK: - Translations

nonisolated struct QuranTranslation: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    static let all: [QuranTranslation] = [
        QuranTranslation(id: "en.sahih", name: "Saheeh International"),
        QuranTranslation(id: "en.hilali", name: "Hilali & Khan"),
        QuranTranslation(id: "en.pickthall", name: "Pickthall"),
        QuranTranslation(id: "en.yusufali", name: "Yusuf Ali"),
        QuranTranslation(id: "en.itani", name: "Clear Qur’an — Talal Itani"),
        QuranTranslation(id: "en.asad", name: "Muhammad Asad"),
        QuranTranslation(id: "en.arberry", name: "A. J. Arberry"),
        QuranTranslation(id: "en.maududi", name: "Abul Ala Maududi"),
        QuranTranslation(id: "en.qarai", name: "Qarai"),
        QuranTranslation(id: "en.shakir", name: "Shakir"),
        QuranTranslation(id: "en.sarwar", name: "Muhammad Sarwar"),
        QuranTranslation(id: "en.wahiduddin", name: "Wahiduddin Khan"),
        QuranTranslation(id: "en.daryabadi", name: "Daryabadi"),
        QuranTranslation(id: "en.qaribullah", name: "Qaribullah & Darwish"),
        QuranTranslation(id: "en.mubarakpuri", name: "Mubarakpuri"),
        QuranTranslation(id: "en.ahmedali", name: "Ahmed Ali"),
        QuranTranslation(id: "en.ahmedraza", name: "Ahmed Raza Khan"),
    ]

    static let defaultID = "en.sahih"

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }
}

// MARK: - Client

nonisolated struct QuranAPI: Sendable {
    static let shared = QuranAPI()

    /// Total ayahs in the Quran — the range the verse of the day picks from.
    static let totalAyahs = 6236

    private static let arabicEdition = "quran-uthmani"
    private static let base = "https://api.alquran.cloud/v1"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: Requests

    func surahList() async throws -> [Surah] {
        try await get("\(Self.base)/surah", as: [Surah].self)
    }

    /// Arabic and translation arrive in a single request, already aligned by ayah number.
    func surah(_ number: Int, translation: String) async throws -> SurahText {
        let editions = try await get(
            "\(Self.base)/surah/\(number)/editions/\(Self.arabicEdition),\(translation)",
            as: [WireSurahEdition].self
        )

        guard let arabic = editions.first(where: { $0.edition.identifier == Self.arabicEdition }),
              let translated = editions.first(where: { $0.edition.identifier != Self.arabicEdition })
        else { throw QuranError.missingEdition }

        let translationsByAyah = Dictionary(
            translated.ayahs.map { ($0.numberInSurah, $0.text) },
            uniquingKeysWith: { first, _ in first }
        )

        var hasBasmala = false
        let ayahs = arabic.ayahs.map { wire -> Ayah in
            var text = QuranText.clean(wire.text)
            if wire.numberInSurah == 1, QuranText.expectsBasmalaHeader(surah: number) {
                let stripped = QuranText.strippingBasmala(from: text)
                text = stripped.text
                hasBasmala = stripped.removed
            }
            return Ayah(
                numberInSurah: wire.numberInSurah,
                numberInQuran: wire.number,
                arabic: text,
                translation: QuranText.clean(translationsByAyah[wire.numberInSurah] ?? ""),
                juz: wire.juz,
                page: wire.page,
                hasSajda: wire.sajda.isSajda
            )
        }

        return SurahText(
            surah: Surah(
                number: arabic.number,
                name: QuranText.clean(arabic.name),
                englishName: arabic.englishName,
                englishNameTranslation: arabic.englishNameTranslation,
                numberOfAyahs: arabic.numberOfAyahs,
                revelationType: arabic.revelationType
            ),
            ayahs: ayahs,
            hasBasmala: hasBasmala,
            translationEdition: translation
        )
    }

    func ayah(_ number: Int, translation: String) async throws -> DailyAyah {
        let editions = try await get(
            "\(Self.base)/ayah/\(number)/editions/\(Self.arabicEdition),\(translation)",
            as: [WireAyahDetail].self
        )

        guard let arabic = editions.first(where: { $0.edition.identifier == Self.arabicEdition }),
              let translated = editions.first(where: { $0.edition.identifier != Self.arabicEdition })
        else { throw QuranError.missingEdition }

        // A standalone ayah 1 still arrives with the Basmala glued on; drop it so the verse
        // reads as itself.
        var text = QuranText.clean(arabic.text)
        if arabic.numberInSurah == 1, QuranText.expectsBasmalaHeader(surah: arabic.surah.number) {
            text = QuranText.strippingBasmala(from: text).text
        }

        return DailyAyah(
            ref: AyahRef(surah: arabic.surah.number, ayah: arabic.numberInSurah),
            surahEnglishName: arabic.surah.englishName,
            arabic: text,
            translation: QuranText.clean(translated.text)
        )
    }

    func search(_ query: String, translation: String) async throws -> [QuranSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return [] }

        do {
            let result = try await get(
                "\(Self.base)/search/\(encoded)/all/\(translation)",
                as: WireSearchResult.self
            )
            return result.matches.map {
                QuranSearchMatch(
                    ref: AyahRef(surah: $0.surah.number, ayah: $0.numberInSurah),
                    surahEnglishName: $0.surah.englishName,
                    text: QuranText.clean($0.text)
                )
            }
        } catch QuranError.badStatus(404) {
            // The API answers a search with no hits with a 404 rather than an empty list.
            return []
        }
    }

    // MARK: Transport

    private func get<T: Decodable>(_ urlString: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: urlString) else { throw QuranError.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .dataNotAllowed {
            throw QuranError.offline
        } catch {
            throw QuranError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuranError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(Envelope<T>.self, from: data).data
        } catch {
            throw QuranError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire Format

private nonisolated struct Envelope<T: Decodable>: Decodable {
    let code: Int
    let data: T
}

private nonisolated struct WireEdition: Decodable {
    let identifier: String
}

private nonisolated struct WireSurahEdition: Decodable {
    let number: Int
    let name: String
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String
    let ayahs: [WireAyah]
    let edition: WireEdition
}

private nonisolated struct WireAyah: Decodable {
    let number: Int
    let numberInSurah: Int
    let text: String
    let juz: Int
    let page: Int
    let sajda: FlexibleSajda
}

private nonisolated struct WireAyahDetail: Decodable {
    let numberInSurah: Int
    let text: String
    let edition: WireEdition
    let surah: WireSurahSummary
}

private nonisolated struct WireSurahSummary: Decodable {
    let number: Int
    let englishName: String
}

private nonisolated struct WireSearchResult: Decodable {
    let count: Int
    let matches: [Match]

    struct Match: Decodable {
        let numberInSurah: Int
        let text: String
        let surah: WireSurahSummary
    }
}

/// `sajda` is `false` on ordinary verses but an object like
/// `{"id":10,"recommended":false,"obligatory":true}` on prostration verses. Decoding it as a
/// plain `Bool` throws partway through Surah As-Sajda.
private nonisolated struct FlexibleSajda: Decodable {
    let isSajda: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            isSajda = flag
        } else {
            isSajda = true
        }
    }
}
