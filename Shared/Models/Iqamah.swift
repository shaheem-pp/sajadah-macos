//
//  Iqamah.swift
//  Shared between Sajadah and SajadahWidgets
//

import Foundation

/// One masjid's congregation (Iqamah) times, as posted on its own site — not computed. Fields
/// are display strings rather than `Date`s because they're read verbatim off a page with no
/// reliable AM/PM or timezone signal, and Maghrib is often posted as the word "Sunset" rather
/// than a clock time.
nonisolated struct IqamahTimes: Codable, Sendable, Equatable {
    var fajr: String
    var dhuhr: String
    var asr: String
    var maghrib: String
    var isha: String
    var jummah1: String?
    var jummah2: String?

    /// The posted value for one of the five daily prayers — nil for `.sunrise`, which never
    /// has an Iqamah, and no slot for Jummah, which isn't a daily concept.
    func time(for prayer: Prayer) -> String? {
        switch prayer {
        case .fajr: fajr
        case .sunrise: nil
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    /// The actual instant `time(for:)` refers to, on the same calendar day as `athaanDate` —
    /// Iqamah is always the same day as its own Adhan. `nil` when the posted text isn't a plain
    /// clock time Sajadah can parse (most commonly Maghrib, often posted as "Sunset" rather
    /// than a time), in which case callers should treat it the same as "unknown".
    func date(for prayer: Prayer, onSameDayAs athaanDate: Date, timeZone: TimeZone) -> Date? {
        guard let text = time(for: prayer) else { return nil }
        return Self.parseClockTime(text, onSameDayAs: athaanDate, timeZone: timeZone)
    }

    private static func parseClockTime(_ text: String, onSameDayAs reference: Date, timeZone: TimeZone) -> Date? {
        // Normalises "6:00AM" / "6:00 A.M." / "6:00  am" down to one shape ("6:00 AM") before
        // handing it to DateFormatter, since the scraper's own regex allows any of those.
        let cleaned = text
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: #"\s*([AaPp][Mm])$"#, with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        guard let timeOnly = formatter.date(from: cleaned) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: reference)
        let time = calendar.dateComponents([.hour, .minute], from: timeOnly)
        return calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: time.hour, minute: time.minute
        ))
    }
}
