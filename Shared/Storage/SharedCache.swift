//
//  SharedCache.swift
//  Shared between Sajadah and SajadahWidgets
//

import Foundation

// MARK: - On-disk formats

/// The prayer timings cache. Shared rather than private to the store, because the widget
/// extension reads the same file.
nonisolated struct PrayerCacheFile: Codable, Sendable {
    var days: [String: DayTimings]
    var fetchedMonths: [String]
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var method: Int
    var school: Int
}

nonisolated struct DailyAyahCache: Codable, Sendable {
    let dayKey: String
    let edition: String
    let ayah: DailyAyah
}

nonisolated struct IqamahCacheFile: Codable, Sendable {
    var times: IqamahTimes
    /// nil when `times` was computed locally (offset mode) rather than scraped from a page.
    var sourceURLString: String?
    var fetchedAt: Date
}

nonisolated enum CacheFileName {
    static let prayerTimes = "prayer-cache.json"
    static let prayerLog = "prayer-log.json"
    static let dailyAyah = "quran/daily.json"
    static let iqamah = "iqamah-cache.json"
    /// Not mirrored to the widget container: widgets have no use for it.
    static let updateCheck = "update-check.json"
}

// MARK: - Snapshot

/// Everything a widget needs, read straight off disk.
///
/// Widgets never hit the network: the app keeps the cache fresh, and a widget that quietly
/// fails to load simply has no `today`, which the views render as "open Sajadah".
nonisolated struct SajadahSnapshot: Sendable {
    var days: [String: DayTimings] = [:]
    var log: [String: DayLog] = [:]
    var placeName: String?
    var dailyAyah: DailyAyah?
    var iqamah: IqamahTimes?
    /// The host of whatever page `iqamah` was scraped from (e.g. "mwcanada.org") — a trust
    /// caption for the widget, same idea as `placeName`.
    var iqamahSourceHost: String?

    /// Sorted across every cached day, so the next-prayer search crosses midnight naturally.
    var events: [PrayerEvent] = []

    var timeZone: TimeZone {
        days.values.max { $0.dayKey < $1.dayKey }?.timeZone ?? .current
    }

    var hasData: Bool { !days.isEmpty }

    func dayKey(for date: Date) -> String {
        DayKey.make(for: date, in: timeZone)
    }

    func today(at date: Date) -> DayTimings? {
        days[dayKey(for: date)]
    }

    func nextEvent(after date: Date) -> PrayerEvent? {
        events.first { $0.date > date && $0.prayer.isPrayer }
    }

    func currentStreak(at date: Date) -> Int {
        log.currentStreak(asOf: dayKey(for: date))
    }

    func prayedCount(at date: Date) -> Int {
        log[dayKey(for: date)]?.prayed.count ?? 0
    }

    func state(for prayer: Prayer, at date: Date) -> PrayerLogState? {
        log[dayKey(for: date)]?.state(for: prayer)
    }

    // MARK: Loading

    static func load() -> SajadahSnapshot {
        var snapshot = SajadahSnapshot()

        if let cache: PrayerCacheFile = decode(CacheFileName.prayerTimes, isoDates: true) {
            snapshot.days = cache.days
            snapshot.placeName = cache.placeName
        }
        snapshot.log = decode(CacheFileName.prayerLog) ?? [:]
        if let daily: DailyAyahCache = decode(CacheFileName.dailyAyah) {
            snapshot.dailyAyah = daily.ayah
        }
        if let cache: IqamahCacheFile = decode(CacheFileName.iqamah, isoDates: true) {
            snapshot.iqamah = cache.times
            snapshot.iqamahSourceHost = cache.sourceURLString.flatMap { URL(string: $0)?.host }
        }
        snapshot.events = snapshot.days.values
            .flatMap(\.events)
            .sorted { $0.date < $1.date }

        return snapshot
    }

    private static func decode<T: Decodable>(_ name: String, isoDates: Bool = false) -> T? {
        // `AppFiles.readData` walks every location this process might be able to read from —
        // the App Group container on a signed build, the mirror in this extension's own
        // container otherwise. See AppFiles for why the second one has to exist.
        guard let data = AppFiles.readData(for: name) else { return nil }
        let decoder = JSONDecoder()
        if isoDates { decoder.dateDecodingStrategy = .iso8601 }
        return try? decoder.decode(T.self, from: data)
    }
}

// MARK: - Deep links

/// URLs widgets hand back to the app when tapped.
nonisolated enum SajadahLink {
    static let scheme = "sajadah"

    static let today = URL(string: "\(scheme)://today")!

    static func ayah(_ ref: AyahRef) -> URL {
        URL(string: "\(scheme)://ayah/\(ref.surah)/\(ref.ayah)") ?? today
    }

    /// Parses a link back into a destination. Returns nil for anything unrecognised.
    static func parse(_ url: URL) -> AyahRef? {
        guard url.scheme == scheme, url.host == "ayah" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let surah = Int(parts[0]), let ayah = Int(parts[1]) else { return nil }
        return AyahRef(surah: surah, ayah: ayah)
    }
}
