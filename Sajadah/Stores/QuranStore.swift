//
//  QuranStore.swift
//  Sajadah
//

import Foundation
import Observation

/// Owns Quran text: fetching surahs, caching them to disk, the verse of the day, and search.
///
/// Follows the same shape as `PrayerTimesStore` — cache to disk, keep showing what's cached
/// when a fetch fails, and flag it rather than blanking the view.
@Observable
final class QuranStore {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: Observed state

    private(set) var surahs: [Surah] = []
    private(set) var listState: LoadState = .idle

    private(set) var texts: [Int: SurahText] = [:]
    private(set) var textStates: [Int: LoadState] = [:]

    private(set) var dailyAyah: DailyAyah?

    private(set) var searchResults: [QuranSearchMatch] = []
    private(set) var searchState: LoadState = .idle
    private(set) var lastSearchQuery = ""

    // MARK: Private state

    @ObservationIgnored private let api = QuranAPI.shared
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var inFlight: Set<Int> = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var dailyAyahDayKey: String?

    private var translation: String {
        settings?.translationEdition ?? QuranTranslation.defaultID
    }

    init() {
        loadSurahListFromDisk()
    }

    func configure(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Surah list

    func loadSurahList() {
        guard surahs.isEmpty else { return }
        listState = .loading

        Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await api.surahList()
                surahs = list
                listState = .loaded
                if let url = AppFiles.url(for: "quran/surahs.json"),
                   let data = try? JSONEncoder().encode(list) {
                    try? data.write(to: url, options: .atomic)
                }
            } catch {
                // A cached list is enough to browse with; only complain if we have nothing.
                listState = surahs.isEmpty
                    ? .failed(Self.message(for: error))
                    : .loaded
            }
        }
    }

    func surah(numbered number: Int) -> Surah? {
        surahs.first { $0.number == number }
    }

    // MARK: Surah text

    func text(for number: Int) -> SurahText? { texts[number] }

    func state(for number: Int) -> LoadState { textStates[number] ?? .idle }

    /// Loads a surah, preferring the disk cache. Safe to call repeatedly — concurrent calls
    /// for the same surah collapse into one request.
    func loadSurah(_ number: Int) {
        if let cached = texts[number], cached.translationEdition == translation { return }
        guard !inFlight.contains(number) else { return }

        if let cached = readTextFromDisk(number), cached.translationEdition == translation {
            texts[number] = cached
            textStates[number] = .loaded
            return
        }

        inFlight.insert(number)
        textStates[number] = .loading
        let edition = translation

        Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(number) }
            do {
                let result = try await api.surah(number, translation: edition)
                // The user may have switched translation while this was in flight.
                guard edition == translation else { return }
                texts[number] = result
                textStates[number] = .loaded
                writeTextToDisk(result)
            } catch {
                textStates[number] = .failed(Self.message(for: error))
            }
        }
    }

    /// Drops every cached surah — the text is tied to a translation edition, so switching
    /// edition makes all of it wrong.
    func invalidateTexts() {
        texts = [:]
        textStates = [:]
        dailyAyah = nil
        dailyAyahDayKey = nil
        AppFiles.removeDirectory("quran/texts")
    }

    // MARK: Verse of the day

    func refreshDailyAyah(dayKey: String) {
        guard dailyAyahDayKey != dayKey || dailyAyah == nil else { return }
        dailyAyahDayKey = dayKey

        if let cached = readDailyFromDisk(dayKey: dayKey), cached.0 == translation {
            dailyAyah = cached.1
            return
        }

        let number = Self.dailyAyahNumber(for: dayKey)
        let edition = translation

        Task { [weak self] in
            guard let self else { return }
            guard let result = try? await api.ayah(number, translation: edition) else { return }
            guard edition == translation, dailyAyahDayKey == dayKey else { return }
            dailyAyah = result
            writeDailyToDisk(result, dayKey: dayKey, edition: edition)
        }
    }

    /// FNV-1a over the day key. Swift's own `Hasher` is seeded per process, so it would hand
    /// out a different verse every launch; this is stable, and mixing well means consecutive
    /// days land far apart rather than walking through the Quran in order.
    static func dailyAyahNumber(for dayKey: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in dayKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(QuranAPI.totalAyahs)) + 1
    }

    // MARK: Search

    func search(_ query: String) {
        searchTask?.cancel()
        lastSearchQuery = query

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchState = .idle
            return
        }

        searchState = .loading
        let edition = translation

        searchTask = Task { [weak self] in
            guard let self else { return }
            // Debounce so a request doesn't go out on every keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            do {
                let matches = try await api.search(trimmed, translation: edition)
                guard !Task.isCancelled else { return }
                searchResults = matches
                searchState = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchState = .failed(Self.message(for: error))
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchState = .idle
        lastSearchQuery = ""
    }

    // MARK: Persistence

    private func loadSurahListFromDisk() {
        guard let url = AppFiles.url(for: "quran/surahs.json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Surah].self, from: data) else { return }
        surahs = list
        listState = .loaded
    }

    private func readTextFromDisk(_ number: Int) -> SurahText? {
        guard let url = AppFiles.url(for: "quran/texts/surah-\(number).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SurahText.self, from: data)
    }

    private func writeTextToDisk(_ text: SurahText) {
        guard let url = AppFiles.url(for: "quran/texts/surah-\(text.surah.number).json"),
              let data = try? JSONEncoder().encode(text) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func readDailyFromDisk(dayKey: String) -> (String, DailyAyah)? {
        guard let url = AppFiles.url(for: CacheFileName.dailyAyah),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(DailyAyahCache.self, from: data),
              stored.dayKey == dayKey else { return nil }
        return (stored.edition, stored.ayah)
    }

    private func writeDailyToDisk(_ ayah: DailyAyah, dayKey: String, edition: String) {
        guard let data = try? JSONEncoder().encode(
            DailyAyahCache(dayKey: dayKey, edition: edition, ayah: ayah)
        ) else { return }
        AppFiles.write(data, to: CacheFileName.dailyAyah)
    }

    private static func message(for error: Error) -> String {
        (error as? QuranError)?.errorDescription ?? error.localizedDescription
    }
}
