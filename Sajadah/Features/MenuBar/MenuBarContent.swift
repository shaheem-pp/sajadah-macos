//
//  MenuBarContent.swift
//  Sajadah
//

import Foundation

/// Everything the menubar item shows, as data. Split into parts rather than one string so the
/// countdown can be styled differently from the prayer name.
nonisolated struct MenuBarContent: Equatable, Sendable {
    /// Which clock `countdown`/`clockTime` are counting down to — never both at once. Once a
    /// prayer's Adhan has passed but its Iqamah (per the masjid's posted time) hasn't, this
    /// flips to `.iqamah` and the countdown/clock retarget to that instead.
    enum Moment: Equatable, Sendable {
        case athaan
        case iqamah
    }

    var icon: String
    var prayer: String
    var countdown: String
    /// Pre-formatted by the caller — this type is `nonisolated` and `TimeFormatting` is
    /// main-actor, so formatting happens on the way in rather than here.
    var clockTime: String
    /// The prayer `countdown`/`clockTime` refer to, kept as the real case rather than just its
    /// display string — so a caller can look up other per-prayer data off this already-debounced
    /// value instead of a second, un-debounced read of the store's live `nextEvent`, which
    /// changes every second right along with `now`.
    var prayerCase: Prayer?
    var moment: Moment = .athaan

    static let placeholder = MenuBarContent(icon: "moon.stars", prayer: "Sajadah", countdown: "")

    /// Used for the accessibility description and as the fallback if rendering ever fails.
    var combined: String {
        let subject = moment == .iqamah ? "\(prayer) Iqamah" : prayer
        return countdown.isEmpty ? subject : "\(subject) \(countdown)"
    }

    init(
        icon: String, prayer: String, countdown: String, clockTime: String = "",
        prayerCase: Prayer? = nil, moment: Moment = .athaan
    ) {
        self.icon = icon
        self.prayer = prayer
        self.countdown = countdown
        self.clockTime = clockTime
        self.prayerCase = prayerCase
        self.moment = moment
    }

    /// The Adhan-countdown case: the ordinary "next prayer" reading.
    init(next event: PrayerEvent?, at now: Date, clockTime: String) {
        guard let event else {
            self = .placeholder
            return
        }

        icon = event.prayer.systemImage
        prayer = event.prayer.displayName
        prayerCase = event.prayer
        self.clockTime = clockTime
        moment = .athaan
        countdown = Self.countdownText(from: now, until: event.date)
    }

    // Minutes, not seconds: the menubar only needs to change once a minute, and a ticking
    // seconds counter up there is a distraction rather than information.
    static func countdownText(from now: Date, until date: Date) -> String {
        let totalMinutes = Int(max(0, date.timeIntervalSince(now))) / 60
        return switch totalMinutes {
        case ..<1: "now"
        case ..<60: "\(totalMinutes)m"
        default: "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
    }
}
