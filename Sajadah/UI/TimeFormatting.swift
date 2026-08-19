//
//  TimeFormatting.swift
//  Sajadah
//

import Foundation

/// Shared clock and countdown formatting, so the menubar, the popover and the window can
/// never disagree about how a time is written.
@MainActor
enum TimeFormatting {
    private static let formatter = DateFormatter()

    /// Times are rendered in the timezone the timings were calculated for, not the Mac's —
    /// they match the prayer times a local mosque would post.
    static func clock(_ date: Date, use24Hour: Bool, timeZone: TimeZone) -> String {
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    /// "1h 23m" when far out, "23m 45s" when close — seconds only appear when they matter.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}
