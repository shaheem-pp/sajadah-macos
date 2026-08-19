//
//  MenuBarContent.swift
//  Sajadah
//

import Foundation

/// Everything the menubar item shows, as data. Split into parts rather than one string so the
/// countdown can be styled differently from the prayer name.
nonisolated struct MenuBarContent: Equatable, Sendable {
    var icon: String
    var prayer: String
    var countdown: String

    static let placeholder = MenuBarContent(icon: "moon.stars", prayer: "Sajadah", countdown: "")

    /// Used for the accessibility description and as the fallback if rendering ever fails.
    var combined: String {
        countdown.isEmpty ? prayer : "\(prayer) \(countdown)"
    }

    init(icon: String, prayer: String, countdown: String) {
        self.icon = icon
        self.prayer = prayer
        self.countdown = countdown
    }

    init(next event: PrayerEvent?, at now: Date) {
        guard let event else {
            self = .placeholder
            return
        }

        icon = event.prayer.systemImage
        prayer = event.prayer.displayName

        // Minutes, not seconds: the menubar only needs to change once a minute, and a
        // ticking seconds counter up there is a distraction rather than information.
        let totalMinutes = Int(max(0, event.date.timeIntervalSince(now))) / 60
        countdown = switch totalMinutes {
        case ..<1: "now"
        case ..<60: "\(totalMinutes)m"
        default: "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
    }
}
