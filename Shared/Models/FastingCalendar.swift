//
//  FastingCalendar.swift
//  Sajadah
//

import Foundation

/// Why a given day is a voluntary fasting day.
nonisolated enum FastingReason: String, Codable, Sendable, Equatable {
    case monday
    case thursday
    case whiteDay

    var displayName: String {
        switch self {
        case .monday: "Monday"
        case .thursday: "Thursday"
        case .whiteDay: "white days"
        }
    }
}

nonisolated extension [FastingReason] {
    /// "Monday", "white days", "Monday & white days".
    var joined: String { map(\.displayName).joined(separator: " & ") }
}

/// The switches the widget needs mirrored, since it can't read defaults.
nonisolated struct FastingPreferences: Codable, Sendable, Equatable {
    var enabled = false
    var mondayThursday = true
    var whiteDays = true
}

/// Which days are sunnah fasting days. Pure: the store and the widget both ask it, and the
/// answer must not depend on who asked.
nonisolated enum FastingCalendar {

    /// Why `day` is a fasting day, in display order; empty when it isn't one. Ramadan is
    /// skipped because everyone is already fasting, and the forbidden days win over any
    /// reason to fast — 13 Dhū al-Ḥijjah is a white day nobody may fast.
    static func reasons(
        for day: DayTimings,
        hijri: HijriDate,
        preferences: FastingPreferences
    ) -> [FastingReason] {
        guard preferences.enabled, !hijri.isRamadan, !hijri.isFastingForbidden else { return [] }
        var reasons: [FastingReason] = []

        if preferences.mondayThursday {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = day.timeZone
            // Read off Dhuhr, which is unambiguously inside the day. 1 is Sunday.
            switch calendar.component(.weekday, from: day.dhuhr) {
            case 2: reasons.append(.monday)
            case 5: reasons.append(.thursday)
            default: break
            }
        }
        if preferences.whiteDays, hijri.isWhiteDay {
            reasons.append(.whiteDay)
        }
        return reasons
    }

    /// The label beside the Hijri date. Today's fast shows until Maghrib ends it; tomorrow's
    /// appears only after that — the evening is when a fast is decided on, and a label all
    /// day Sunday about Monday would be noise on the day it isn't about.
    static func indicator(
        todayReasons: [FastingReason],
        tomorrowReasons: [FastingReason],
        maghrib: Date,
        now: Date,
        compact: Bool
    ) -> String? {
        if now < maghrib {
            guard !todayReasons.isEmpty else { return nil }
            return compact ? "Fasting day" : "Fasting day · \(todayReasons.joined)"
        }
        guard !tomorrowReasons.isEmpty else { return nil }
        return compact ? "Fasting tomorrow" : "Fasting tomorrow · \(tomorrowReasons.joined)"
    }
}

// MARK: - Lookups

nonisolated extension Dictionary where Key == String, Value == DayTimings {

    /// `FastingCalendar.reasons` for the civil day `dayKey`, on the adjusted Hijri date.
    /// A fast runs from Fajr to Maghrib of a civil day whichever way the displayed date is
    /// read, so this deliberately ignores `changesAtMaghrib`.
    func fastingReasons(
        on dayKey: String,
        hijri: HijriPreferences,
        fasting: FastingPreferences,
        timeZone: TimeZone
    ) -> [FastingReason] {
        guard fasting.enabled, let day = self[dayKey],
              let date = hijriDate(for: dayKey, adjustedBy: hijri.adjustmentDays, timeZone: timeZone) else {
            return []
        }
        return FastingCalendar.reasons(for: day, hijri: date, preferences: fasting)
    }

    func fastingIndicator(
        at now: Date,
        hijri: HijriPreferences,
        fasting: FastingPreferences,
        timeZone: TimeZone,
        compact: Bool
    ) -> String? {
        let todayKey = DayKey.make(for: now, in: timeZone)
        guard fasting.enabled, let today = self[todayKey], let tomorrowKey = DayKey.next(todayKey) else {
            return nil
        }
        return FastingCalendar.indicator(
            todayReasons: fastingReasons(on: todayKey, hijri: hijri, fasting: fasting, timeZone: timeZone),
            tomorrowReasons: fastingReasons(on: tomorrowKey, hijri: hijri, fasting: fasting, timeZone: timeZone),
            maghrib: today.maghrib,
            now: now,
            compact: compact
        )
    }
}
