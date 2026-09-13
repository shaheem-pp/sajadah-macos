//
//  HijriDate.swift
//  Sajadah
//

import Foundation

/// A date in the Islamic calendar, as the Aladhan API assigns one to each Gregorian day.
///
/// Explicitly `nonisolated`: this module defaults to `MainActor` isolation, and widget
/// timeline providers read these off the main actor.
nonisolated struct HijriDate: Codable, Sendable, Equatable, Hashable {
    let day: Int
    let month: Int
    let year: Int

    /// Aladhan's own transliterations. A date computed locally has to read identically to one
    /// that came off the wire, and Foundation's `monthSymbols` spell these differently.
    static let monthNames = [
        "Muḥarram", "Ṣafar", "Rabīʿ al-awwal", "Rabīʿ al-thānī",
        "Jumādá al-ūlá", "Jumādá al-ākhirah", "Rajab", "Shaʿbān",
        "Ramaḍān", "Shawwāl", "Dhū al-Qaʿdah", "Dhū al-Ḥijjah",
    ]

    var monthName: String {
        (1...12).contains(month) ? Self.monthNames[month - 1] : ""
    }

    /// The same shape as the string the API produced, so nothing on screen moves.
    var formatted: String { "\(day) \(monthName) \(year) AH" }

    /// "\(day) \(monthName)" — for prose that already says which year it is.
    var dayAndMonth: String { "\(day) \(monthName)" }

    /// The 13th, 14th and 15th — the nights the moon is full, and the three days the Prophet ﷺ
    /// recommended fasting each month.
    var isWhiteDay: Bool { (13...15).contains(day) }

    var isRamadan: Bool { month == 9 }

    /// 9 Muḥarram — the day the Prophet ﷺ meant to fast alongside Ashura.
    var isTasua: Bool { month == 1 && day == 9 }

    /// 10 Muḥarram.
    var isAshura: Bool { month == 1 && day == 10 }

    /// 9 Dhū al-Ḥijjah — the day of standing at Arafah, and a fast for everyone not there.
    var isArafah: Bool { month == 12 && day == 9 }

    /// Eid al-Fitr, Eid al-Adha and the three days of Tashreeq after it. Fasting on these is
    /// forbidden, which outranks any reason to — 13 Dhū al-Ḥijjah is a white day nobody fasts.
    var isFastingForbidden: Bool {
        (month == 10 && day == 1) || (month == 12 && (10...13).contains(day))
    }

    /// Umm al-Qura arithmetic — the tables Aladhan's `HJCoSA` calendar starts from before
    /// Saudi Arabia's sighting announcements adjust them. Used only for a day the cache
    /// doesn't hold, so it is at most a day out and usually not at all.
    static func ummAlQura(for date: Date, in timeZone: TimeZone) -> HijriDate? {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let day = parts.day, let month = parts.month, let year = parts.year else { return nil }
        return HijriDate(day: day, month: month, year: year)
    }
}

/// How the user wants the Hijri date read. Written into the timings cache as well as
/// defaults, because the widget extension can read the one and not the other.
nonisolated struct HijriPreferences: Codable, Sendable, Equatable {
    /// Days to shift by. Aladhan follows Saudi Arabia's announcements; a community that
    /// sighted the moon a day earlier is +1 from that, and nothing here can tell which.
    var adjustmentDays = 0
    /// The Islamic day begins at sunset. A printed calendar changes at midnight, and someone
    /// checking against one at 9pm would otherwise think the app a day ahead.
    var changesAtMaghrib = true
}

// MARK: - Lookups

/// One lookup shared by the store and the widget snapshot, so the two can never disagree
/// about what an adjusted date is.
nonisolated extension Dictionary where Key == String, Value == DayTimings {

    /// The Hijri date the API assigns to the civil day `dayKey`, shifted by `days`: the
    /// adjusted date for a day is simply the unadjusted date of a neighbouring one, which is
    /// what keeps month lengths right without any Hijri arithmetic of our own.
    func hijriDate(for dayKey: String, adjustedBy days: Int, timeZone: TimeZone) -> HijriDate? {
        guard let lookup = DayKey.shifted(dayKey, by: days) else { return nil }
        if let cached = self[lookup]?.hijriDate { return cached }
        guard let noon = DayKey.date(lookup, in: timeZone) else { return nil }
        return HijriDate.ummAlQura(for: noon, in: timeZone)
    }

    /// The date to show at `now`. After today's Maghrib, when the preference says so, that is
    /// tomorrow's — the new Islamic day has begun even though the civil one hasn't ended.
    func displayedHijriDate(at now: Date, preferences: HijriPreferences, timeZone: TimeZone) -> HijriDate? {
        let todayKey = DayKey.make(for: now, in: timeZone)
        var key = todayKey
        if preferences.changesAtMaghrib,
           let today = self[todayKey], now >= today.maghrib,
           let tomorrow = DayKey.next(todayKey) {
            key = tomorrow
        }
        return hijriDate(for: key, adjustedBy: preferences.adjustmentDays, timeZone: timeZone)
    }
}
