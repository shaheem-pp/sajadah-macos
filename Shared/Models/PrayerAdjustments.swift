//
//  PrayerAdjustments.swift
//  Sajadah
//

import Foundation

/// Minutes added to each computed Adhan time, for a community whose calendar runs a few
/// minutes off the method it nominally follows. Off by default; the five offsets are kept
/// while the switch is off, so turning it back on restores them.
///
/// Written into the timings cache as well as defaults, because the widget extension reads the
/// one and not the other. The cache itself holds the *unadjusted* times: applying these is
/// arithmetic every reader can do, and keeping the raw times means a change needs no refetch.
nonisolated struct PrayerAdjustments: Codable, Sendable, Equatable {
    var enabled = false
    var fajr = 0
    var dhuhr = 0
    var asr = 0
    var maghrib = 0
    var isha = 0

    /// Sunrise has no Adhan and so no adjustment.
    func minutes(for prayer: Prayer) -> Int {
        switch prayer {
        case .fajr: fajr
        case .sunrise: 0
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    /// Whether applying this would change anything at all.
    var isEffective: Bool {
        enabled && [fajr, dhuhr, asr, maghrib, isha].contains { $0 != 0 }
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, fajr, dhuhr, asr, maghrib, isha
    }
}

nonisolated extension PrayerAdjustments {
    /// Hand-written for the same reason `FastingPreferences`' is: a cache file written before
    /// a key existed must still decode, in the widget as much as the app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        fajr = try container.decodeIfPresent(Int.self, forKey: .fajr) ?? 0
        dhuhr = try container.decodeIfPresent(Int.self, forKey: .dhuhr) ?? 0
        asr = try container.decodeIfPresent(Int.self, forKey: .asr) ?? 0
        maghrib = try container.decodeIfPresent(Int.self, forKey: .maghrib) ?? 0
        isha = try container.decodeIfPresent(Int.self, forKey: .isha) ?? 0
    }
}

// MARK: - Applying

nonisolated extension DayTimings {
    /// This day with each Adhan moved by its adjustment. Identity when the switch is off, so a
    /// caller can apply it unconditionally.
    func adjusted(by adjustments: PrayerAdjustments) -> DayTimings {
        guard adjustments.isEffective else { return self }
        func shift(_ date: Date, _ prayer: Prayer) -> Date {
            date.addingTimeInterval(TimeInterval(adjustments.minutes(for: prayer) * 60))
        }
        return DayTimings(
            dayKey: dayKey,
            hijri: hijri,
            hijriDate: hijriDate,
            timeZoneIdentifier: timeZoneIdentifier,
            fajr: shift(fajr, .fajr),
            sunrise: sunrise,
            dhuhr: shift(dhuhr, .dhuhr),
            asr: shift(asr, .asr),
            maghrib: shift(maghrib, .maghrib),
            isha: shift(isha, .isha)
        )
    }
}

nonisolated extension Dictionary where Key == String, Value == DayTimings {
    func adjusted(by adjustments: PrayerAdjustments) -> Self {
        guard adjustments.isEffective else { return self }
        return mapValues { $0.adjusted(by: adjustments) }
    }
}
