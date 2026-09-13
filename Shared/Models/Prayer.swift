//
//  Prayer.swift
//  Sajadah
//

import Foundation

// MARK: - Prayer

nonisolated enum Prayer: String, CaseIterable, Codable, Identifiable, Sendable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    /// Sunrise closes the Fajr window rather than being a prayer of its own. It is worth
    /// showing in the list, but we never count down to it or notify about it.
    var isPrayer: Bool { self != .sunrise }

    var systemImage: String {
        switch self {
        case .fajr: "sunrise"
        case .sunrise: "sun.horizon"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon.stars"
        }
    }
}

// MARK: - Prayer Event

/// A single prayer at a concrete instant. Flattening the cache into these is what makes
/// "next prayer" a simple sorted search that naturally crosses midnight.
nonisolated struct PrayerEvent: Identifiable, Hashable, Sendable {
    let prayer: Prayer
    let date: Date

    var id: String { "\(prayer.rawValue)@\(date.timeIntervalSince1970)" }
}

// MARK: - Day Timings

/// One day's timings, in the cache's own shape rather than the API's. Fields are explicit
/// (instead of a `[Prayer: Date]` dictionary) so `Codable` needs no help and the compiler
/// catches a missing prayer.
nonisolated struct DayTimings: Codable, Identifiable, Sendable, Equatable {
    /// `yyyy-MM-dd` in `timeZoneIdentifier` — sortable, and stable across the user's own
    /// timezone changing.
    let dayKey: String
    let hijri: String
    let timeZoneIdentifier: String

    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date

    var id: String { dayKey }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    func time(for prayer: Prayer) -> Date {
        switch prayer {
        case .fajr: fajr
        case .sunrise: sunrise
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    /// Every timing for the day, chronological. Sorted rather than assuming `allCases`
    /// order — at extreme latitudes the API can return timings that overlap or invert.
    var events: [PrayerEvent] {
        Prayer.allCases
            .map { PrayerEvent(prayer: $0, date: time(for: $0)) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Day Keys

nonisolated enum DayKey {
    /// `yyyy-MM-dd` for `date` as seen in `timeZone`. Built by hand from calendar
    /// components so it never depends on the user's locale.
    static func make(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `yyyy-MM` — the key a month of API results is cached under.
    static func month(for date: Date, in timeZone: TimeZone) -> String {
        String(make(for: date, in: timeZone).prefix(7))
    }

    /// The day before `key`.
    static func previous(_ key: String) -> String? { shifted(key, by: -1) }

    /// The day after `key`.
    static func next(_ key: String) -> String? { shifted(key, by: 1) }

    /// `key` moved by `days`. Arithmetic is done in UTC so it walks calendar labels rather
    /// than instants — stepping a day must never be affected by a DST transition.
    static func shifted(_ key: String, by days: Int) -> String? {
        guard let date = date(key, in: Self.utc.timeZone),
              let shifted = Self.utc.date(byAdding: .day, value: days, to: date) else { return nil }
        return make(for: shifted, in: Self.utc.timeZone)
    }

    /// Noon of `key` in `timeZone`. Noon rather than midnight for the same reason the Isha
    /// cutoff anchors on Dhuhr: midday is unambiguously inside the right local day, where
    /// midnight sits on the edge of two.
    static func date(_ key: String, in timeZone: TimeZone) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

// MARK: - Prayer Windows

extension DayTimings {
    /// When a prayer's window closes — the point past which we stop asking whether it was
    /// prayed. Each prayer runs until the next one begins; Isha has no following prayer, so
    /// it runs to a cutoff time the user sets.
    func windowClose(for prayer: Prayer, ishaCutoffMinutes: Int) -> Date? {
        switch prayer {
        case .fajr: sunrise
        case .sunrise: nil
        case .dhuhr: asr
        case .asr: maghrib
        case .maghrib: isha
        case .isha: ishaCutoff(minutesFromMidnight: ishaCutoffMinutes)
        }
    }

    private func ishaCutoff(minutesFromMidnight: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Anchored on Dhuhr because midday is unambiguously inside the right local day.
        let midnight = calendar.startOfDay(for: dhuhr)
        guard let cutoff = calendar.date(byAdding: .minute, value: minutesFromMidnight, to: midnight) else {
            return nil
        }
        // At high latitudes Isha can fall after the cutoff, leaving nothing sensible to ask.
        return cutoff > isha ? cutoff : nil
    }
}
