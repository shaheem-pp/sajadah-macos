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
    /// Lives in defaults too, but the widget can only read this file. Optional so a file
    /// written before it existed still decodes.
    var hijri: HijriPreferences?
    var fasting: FastingPreferences?
    /// `days` are the API's own times; these are applied on the way out, by app and widget alike.
    var adjustments: PrayerAdjustments?
    /// When Isha's window closes, as minutes from midnight — the one setting the widget's
    /// day-phase needs that isn't already in here. Optional for the same reason `hijri` is.
    var ishaCutoffMinutes: Int?
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
    var hijri = HijriPreferences()
    var fasting = FastingPreferences()
    /// Falls back to the app's own default when the cache predates the field.
    var ishaCutoffMinutes = 23 * 60
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

    /// Adjusted, and past Maghrib already tomorrow's — the same rule the app applies.
    func displayedHijriDate(at date: Date) -> HijriDate? {
        days.displayedHijriDate(at: date, preferences: hijri, timeZone: timeZone)
    }

    /// Worded by the widget itself, which has no room for which day it is.
    func fastingIndicator(at date: Date) -> FastingIndicator? {
        days.fastingIndicator(at: date, hijri: hijri, fasting: fasting, timeZone: timeZone)
    }

    func nextEvent(after date: Date) -> PrayerEvent? {
        events.first { $0.date > date && $0.prayer.isPrayer }
    }

    /// The most recent prayer that has already started.
    func currentEvent(at date: Date) -> PrayerEvent? {
        events.last { $0.date <= date && $0.prayer.isPrayer }
    }

    /// Where the clock sits in the day — the same answer the app's hero gives, from the same
    /// rule, so a widget on the desktop and the popover never describe one moment differently.
    func phase(at date: Date) -> DayPhase {
        DayPhase.resolve(
            at: date,
            events: events,
            days: days,
            timeZone: timeZone,
            iqamah: iqamah,
            ishaCutoffMinutes: ishaCutoffMinutes,
            log: log
        )
    }

    /// When the masjid's Iqamah for `event` falls, or nil where the posted value isn't a clock
    /// time — Maghrib is usually "Sunset".
    func iqamahDate(for event: PrayerEvent) -> Date? {
        iqamah?.date(for: event.prayer, onSameDayAs: event.date, timeZone: timeZone)
    }

    /// The next jamaah still ahead. Checked from the prayer in progress first — its Iqamah may
    /// not have happened yet even though its Adhan has — then forward through the timings.
    func nextJamaah(after date: Date) -> (event: PrayerEvent, iqamah: Date)? {
        if let current = currentEvent(at: date), let iqamah = iqamahDate(for: current), iqamah > date {
            return (current, iqamah)
        }
        for event in events where event.prayer.isPrayer && event.date > date {
            if let iqamah = iqamahDate(for: event) { return (event, iqamah) }
        }
        return nil
    }

    /// Whether `prayer`'s time has come today — the app's rule for when a prayer can be logged.
    func isLoggable(_ prayer: Prayer, at date: Date) -> Bool {
        guard let today = today(at: date) else { return false }
        return today.time(for: prayer) <= date
    }

    /// The next fasting day after today, within `limit` days, with the reasons for it. Nil when
    /// fasting reminders are off or nothing falls inside the horizon.
    func nextFastingDay(after date: Date, limit: Int = 45) -> FastingDayStatus? {
        guard fasting.enabled else { return nil }
        var key = dayKey(for: date)
        for _ in 0..<limit {
            guard let next = DayKey.next(key) else { return nil }
            key = next
            guard let hijri = days.hijriDate(for: key, adjustedBy: self.hijri.adjustmentDays, timeZone: timeZone) else { continue }
            let reasons = FastingCalendar.reasons(forDayKey: key, timeZone: timeZone, hijri: hijri, preferences: fasting)
            if !reasons.isEmpty {
                return FastingDayStatus(dayKey: key, hijri: hijri, reasons: reasons)
            }
        }
        return nil
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
            // The same arithmetic the app does, so a widget never shows a different minute.
            snapshot.days = cache.days.adjusted(by: cache.adjustments ?? PrayerAdjustments())
            snapshot.placeName = cache.placeName
            snapshot.hijri = cache.hijri ?? HijriPreferences()
            snapshot.fasting = cache.fasting ?? FastingPreferences()
            snapshot.ishaCutoffMinutes = cache.ishaCutoffMinutes ?? snapshot.ishaCutoffMinutes
        }
        snapshot.log = decode(CacheFileName.prayerLog) ?? [:]
        // Taps made on a widget that the app hasn't folded in yet — so a button that was just
        // pressed shows as pressed, whether or not the app is running.
        WidgetLogInbox.apply(WidgetLogInbox.pending(), to: &snapshot.log)
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
