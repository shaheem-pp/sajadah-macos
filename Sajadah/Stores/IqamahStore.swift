//
//  IqamahStore.swift
//  Sajadah
//

import Foundation
import Observation

/// Owns the masjid Iqamah scrape: fetching it, caching it to disk, and reporting exactly what
/// was and wasn't found so Settings can show a live preview rather than a black box.
///
/// Unlike `PrayerTimesStore` there's no month coverage to manage — one page, one scrape, cached
/// until the next refresh.
@Observable
final class IqamahStore {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: Observed state

    private(set) var loadState: LoadState = .idle
    /// True when a refresh failed but a previously-successful scrape is still being shown.
    private(set) var isStale = false
    private(set) var times: IqamahTimes?
    /// The full per-label breakdown of the most recent attempt, success or failure — what the
    /// Settings preview renders.
    private(set) var lastResult: IqamahScrapeResult?
    private(set) var sourceURLString: String?

    /// The fetched page's own host, e.g. "mwcanada.org" — a trust caption for the UI.
    var sourceHost: String? {
        sourceURLString.flatMap { URL(string: $0)?.host }
    }

    /// Fires only when the on-disk cache actually changes (a new success, or a clear), so a
    /// failed-but-stale refresh doesn't needlessly reload every widget timeline.
    @ObservationIgnored var onTimesChanged: (() -> Void)?

    // MARK: Private state

    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var prayerTimes: PrayerTimesStore?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let scraper = IqamahScraper.shared
    /// The local calendar day this last ticked into an afternoon refresh, so it fires once per
    /// day rather than on every tick once past the boundary.
    @ObservationIgnored private var lastAfternoonRefreshDayKey: String?
    /// The local calendar day last synced at its own rollover. Seeded on the first tick rather
    /// than in `init`, so launching doesn't count as a rollover and double up with the
    /// refresh `AppCoordinator` already does at startup.
    @ObservationIgnored private var lastMidnightSyncDayKey: String?

    /// Local hour an Iqamah re-check counts as "this afternoon" — masjids sometimes correct a
    /// same-day posting, and checking once past midday catches that before Asr/Maghrib/Isha.
    private static let afternoonHour = 12

    // MARK: Init

    init() {
        loadCache()
    }

    func configure(settings: AppSettings, prayerTimes: PrayerTimesStore) {
        self.settings = settings
        self.prayerTimes = prayerTimes
    }

    // MARK: Ticking

    /// Called by the app-wide `Ticker`, same as `PrayerTimesStore.tick(_:)`.
    ///
    /// Two refreshes a day, both driven off the calendar rather than a timer, so they cost
    /// nothing while the app isn't running and need no separate scheduling:
    ///
    ///  - **At midnight**, because a posted schedule belongs to a day and today's is now
    ///    yesterday's. A Mac asleep at midnight syncs on the first tick after it wakes.
    ///  - **In the afternoon**, because masjids sometimes correct a same-day posting, and
    ///    catching that before Asr is the difference between right and wrong for three prayers.
    func tick(_ date: Date) {
        let calendar = Calendar.current
        let todayKey = DayKey.make(for: date, in: calendar.timeZone)

        if lastMidnightSyncDayKey == nil {
            // First tick of this launch. Seed both markers so neither fires immediately —
            // the app has just refreshed on its own.
            lastMidnightSyncDayKey = todayKey
            if calendar.component(.hour, from: date) >= Self.afternoonHour {
                lastAfternoonRefreshDayKey = todayKey
            }
            return
        }

        if todayKey != lastMidnightSyncDayKey {
            lastMidnightSyncDayKey = todayKey
            // A new day's afternoon check is owed again.
            lastAfternoonRefreshDayKey = nil
            refresh()
            return
        }

        guard calendar.component(.hour, from: date) >= Self.afternoonHour else { return }
        guard todayKey != lastAfternoonRefreshDayKey else { return }
        lastAfternoonRefreshDayKey = todayKey
        refresh()
    }

    // MARK: Refresh

    /// Re-derives Iqamah times from whichever source is configured. Safe to call whenever — on
    /// launch, once a day in the afternoon (see `tick(_:)`), and immediately when the source
    /// (mode, URL, or an offset) changes in Settings.
    func refresh() {
        switch settings?.iqamahSourceMode {
        case .offset:
            refreshFromOffsets()
        case .website, nil:
            refreshFromWebsite()
        }
    }

    private func refreshFromWebsite() {
        refreshTask?.cancel()

        let trimmed = settings?.masjidURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            reset()
            return
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized), let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            lastResult = nil
            isStale = times != nil
            loadState = .failed(IqamahScrapeError.badURL.errorDescription ?? "Invalid URL.")
            return
        }

        loadState = .loading
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await scraper.scrape(url: url)
                guard !Task.isCancelled else { return }
                lastResult = result

                if let found = result.times {
                    times = found
                    sourceURLString = normalized
                    isStale = false
                    loadState = .loaded
                    persist(times: found, sourceURLString: normalized)
                } else {
                    isStale = times != nil
                    loadState = .failed(Self.message(for: result))
                }
            } catch {
                guard !Task.isCancelled else { return }
                lastResult = nil
                isStale = times != nil
                loadState = .failed((error as? IqamahScrapeError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Pure local arithmetic — no network, no `Task`, no failure mode. Adhan data not being
    /// loaded yet is the only way this can have nothing to compute from, and `AppCoordinator`
    /// already calls `refresh()` again whenever that data changes, so this just waits quietly.
    private func refreshFromOffsets() {
        refreshTask?.cancel()
        guard let settings, let day = prayerTimes?.today else { return }

        let computed = IqamahOffsetCalculator.times(
            for: day,
            fajr: settings.iqamahOffsetFajr,
            dhuhr: settings.iqamahOffsetDhuhr,
            asr: settings.iqamahOffsetAsr,
            maghrib: settings.iqamahOffsetMaghrib,
            isha: settings.iqamahOffsetIsha,
            use24Hour: settings.use24HourClock
        )

        times = computed
        sourceURLString = nil
        lastResult = nil
        isStale = false
        loadState = .loaded
        persist(times: computed, sourceURLString: nil)
    }

    private static func message(for result: IqamahScrapeResult) -> String {
        let missing = result.missingCoreLabels
        let coreCount = IqamahLabel.allCases.filter(\.isCore).count
        if missing.count == coreCount {
            if let framework = result.jsFrameworkHint {
                return "This page loads its schedule with JavaScript (\(framework)), which Sajadah can’t read. Try “Minutes after Athaan” instead."
            }
            return "Couldn’t find any prayer times on this page. It may use images or JavaScript to show its schedule, which Sajadah can’t read."
        }
        return "Couldn’t find \(missing.map(\.displayName).joined(separator: ", ")) on this page."
    }

    private func reset() {
        refreshTask?.cancel()
        guard times != nil || lastResult != nil || loadState != .idle else { return }
        times = nil
        lastResult = nil
        sourceURLString = nil
        loadState = .idle
        isStale = false
        clearCache()
        onTimesChanged?()
    }

    // MARK: Persistence

    private var cacheURL: URL? { AppFiles.url(for: CacheFileName.iqamah) }

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(IqamahCacheFile.self, from: data) else { return }

        times = cache.times
        sourceURLString = cache.sourceURLString
        loadState = .loaded
    }

    private func persist(times: IqamahTimes, sourceURLString: String?) {
        let cache = IqamahCacheFile(times: times, sourceURLString: sourceURLString, fetchedAt: .now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        AppFiles.write(data, to: CacheFileName.iqamah)
        onTimesChanged?()
    }

    private func clearCache() {
        AppFiles.remove(CacheFileName.iqamah)
    }
}
