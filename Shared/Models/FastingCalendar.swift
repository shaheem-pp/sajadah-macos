//
//  FastingCalendar.swift
//  Sajadah
//

import Foundation

/// Why a given day is a fasting day.
nonisolated enum FastingReason: String, Codable, Sendable, Equatable {
    case monday
    case thursday
    /// 9 Muḥarram. The Prophet ﷺ meant to fast it alongside Ashura, so the two go together.
    case tasua
    /// 10 Muḥarram.
    case ashura
    /// 9 Dhū al-Ḥijjah, for anyone not standing at Arafah that day.
    case arafah
    case whiteDay
    /// The month itself. Not a sunnah — it is here so the month is marked, not because there
    /// is a choice to make about it.
    case ramadan

    var displayName: String {
        switch self {
        case .monday: "Monday"
        case .thursday: "Thursday"
        case .tasua: "Day before Ashura"
        case .ashura: "Ashura"
        case .arafah: "Arafah"
        case .whiteDay: "white days"
        case .ramadan: "Ramadan"
        }
    }

    /// The two reasons that come from the weekday rather than the Hijri date.
    var isWeekday: Bool { self == .monday || self == .thursday }

    /// Whether the evening before a day with this reason gets a reminder. A month of nightly
    /// "fasting tomorrow" is the one notification nobody in Ramadan needs, so the month is
    /// announced once, the evening before it begins.
    func remindsOnEve(of hijri: HijriDate) -> Bool {
        self == .ramadan ? hijri.day == 1 : true
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
    var ashura = true
    var arafah = true

    // Named so the decoder below and the synthesised encoder agree on the keys.
    private enum CodingKeys: String, CodingKey {
        case enabled, mondayThursday, whiteDays, ashura, arafah
    }
}

nonisolated extension FastingPreferences {
    /// Hand-written so a cache written before `ashura` and `arafah` existed still decodes — in
    /// the widget as much as here, where a failed decode is a blank widget rather than an
    /// error. Synthesised `Decodable` treats a missing key as a failure, defaults or not.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mondayThursday = try container.decodeIfPresent(Bool.self, forKey: .mondayThursday) ?? true
        whiteDays = try container.decodeIfPresent(Bool.self, forKey: .whiteDays) ?? true
        ashura = try container.decodeIfPresent(Bool.self, forKey: .ashura) ?? true
        arafah = try container.decodeIfPresent(Bool.self, forKey: .arafah) ?? true
    }
}

/// One civil day's fasting status, on the adjusted Hijri date.
nonisolated struct FastingDayStatus: Identifiable, Sendable, Equatable {
    let dayKey: String
    let hijri: HijriDate
    let reasons: [FastingReason]

    var id: String { dayKey }
    var isFast: Bool { !reasons.isEmpty }
}

/// What the label beside the Hijri date says. Data rather than a string, because one case
/// carries a clock time and the app and the widget format those differently.
nonisolated enum FastingIndicator: Equatable, Sendable {
    /// Today's fast, until Maghrib ends it.
    case fastingToday([FastingReason])
    /// After Maghrib: the fast being decided on.
    case fastingTomorrow([FastingReason])
    /// A day of Ramadan before Maghrib. The date beside this label already says which day of
    /// the month it is; the time the fast ends is the thing worth adding.
    case iftar(Date)
    /// The evening before 1 Ramaḍān.
    case ramadanTomorrow
}

/// Which days are fasting days. Pure: the store and the widget both ask it, and the answer
/// must not depend on who asked.
nonisolated enum FastingCalendar {

    /// Why the civil day `dayKey` is a fasting day, in display order; empty when it isn't one.
    /// The forbidden days win over any reason to fast — 13 Dhū al-Ḥijjah is a white day nobody
    /// may fast — and Ramadan outranks every other reason: "Ramadan & Monday" would be a
    /// strange thing to say about a day everyone is fasting anyway.
    ///
    /// Takes a day key rather than that day's timings so it works for days the cache doesn't
    /// hold yet — the weekday needs no timings at all.
    static func reasons(
        forDayKey dayKey: String,
        timeZone: TimeZone,
        hijri: HijriDate,
        preferences: FastingPreferences
    ) -> [FastingReason] {
        guard preferences.enabled, !hijri.isFastingForbidden else { return [] }
        if hijri.isRamadan { return [.ramadan] }
        var reasons: [FastingReason] = []

        if preferences.mondayThursday, let noon = DayKey.date(dayKey, in: timeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            // Read off noon, which is unambiguously inside the day. 1 is Sunday.
            switch calendar.component(.weekday, from: noon) {
            case 2: reasons.append(.monday)
            case 5: reasons.append(.thursday)
            default: break
            }
        }
        if preferences.ashura {
            if hijri.isTasua { reasons.append(.tasua) }
            if hijri.isAshura { reasons.append(.ashura) }
        }
        if preferences.arafah, hijri.isArafah {
            reasons.append(.arafah)
        }
        if preferences.whiteDays, hijri.isWhiteDay {
            reasons.append(.whiteDay)
        }
        return reasons
    }

    /// The label beside the Hijri date. Today's fast shows until Maghrib ends it; tomorrow's
    /// appears only after that — the evening is when a fast is decided on, and a label all
    /// day Sunday about Monday would be noise on the day it isn't about. Ramadan is the
    /// exception both ways: before Maghrib the useful thing is when iftar is, and after it
    /// only the first night is news, because the date beside the label has already turned.
    static func indicator(
        today: FastingDayStatus?,
        tomorrow: FastingDayStatus?,
        maghrib: Date,
        now: Date
    ) -> FastingIndicator? {
        if now < maghrib {
            guard let today, today.isFast else { return nil }
            return today.reasons.contains(.ramadan) ? .iftar(maghrib) : .fastingToday(today.reasons)
        }
        guard let tomorrow, tomorrow.isFast else { return nil }
        if tomorrow.reasons.contains(.ramadan) {
            return tomorrow.hijri.day == 1 ? .ramadanTomorrow : nil
        }
        return .fastingTomorrow(tomorrow.reasons)
    }
}

// MARK: - Lookups

nonisolated extension Dictionary where Key == String, Value == DayTimings {

    /// The civil day `dayKey`'s fasting status, on the adjusted Hijri date. A fast runs from
    /// Fajr to Maghrib of a civil day whichever way the displayed date is read, so this
    /// deliberately ignores `changesAtMaghrib`. Nil with fasting off, or with no Hijri date
    /// to be had — which the arithmetic fallback makes rare.
    func fastingStatus(
        on dayKey: String,
        hijri: HijriPreferences,
        fasting: FastingPreferences,
        timeZone: TimeZone
    ) -> FastingDayStatus? {
        guard fasting.enabled,
              let date = hijriDate(for: dayKey, adjustedBy: hijri.adjustmentDays, timeZone: timeZone) else {
            return nil
        }
        let reasons = FastingCalendar.reasons(forDayKey: dayKey, timeZone: timeZone, hijri: date, preferences: fasting)
        return FastingDayStatus(dayKey: dayKey, hijri: date, reasons: reasons)
    }

    /// `FastingCalendar.reasons` for the civil day `dayKey`; empty when it isn't a fast.
    func fastingReasons(
        on dayKey: String,
        hijri: HijriPreferences,
        fasting: FastingPreferences,
        timeZone: TimeZone
    ) -> [FastingReason] {
        fastingStatus(on: dayKey, hijri: hijri, fasting: fasting, timeZone: timeZone)?.reasons ?? []
    }

    func fastingIndicator(
        at now: Date,
        hijri: HijriPreferences,
        fasting: FastingPreferences,
        timeZone: TimeZone
    ) -> FastingIndicator? {
        let todayKey = DayKey.make(for: now, in: timeZone)
        guard fasting.enabled, let today = self[todayKey], let tomorrowKey = DayKey.next(todayKey) else {
            return nil
        }
        return FastingCalendar.indicator(
            today: fastingStatus(on: todayKey, hijri: hijri, fasting: fasting, timeZone: timeZone),
            tomorrow: fastingStatus(on: tomorrowKey, hijri: hijri, fasting: fasting, timeZone: timeZone),
            maghrib: today.maghrib,
            now: now
        )
    }
}
