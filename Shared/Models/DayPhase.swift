//
//  DayPhase.swift
//  Sajadah
//

import Foundation

/// Where the clock currently sits in the day, and therefore which question the app should be
/// answering.
///
/// The window used to answer one question at every hour — *when is the next Adhan* — but the
/// question a person actually has moves with the clock: how long until the Adhan, then whether
/// jamaah is still catchable, then how much of the window is left. Deriving all of that once,
/// here, is what stops the hero, the popover and the menubar each deciding separately.
nonisolated enum DayPhase: Equatable, Sendable {

    /// No prayer's window is open — waiting for the next Adhan. Also covers the stretch
    /// between Isha's window closing and tomorrow's Fajr.
    case awaitingAdhan(next: PrayerEvent)

    /// The Adhan has gone and the masjid's Iqamah hasn't. The only part of the day where
    /// minutes change what someone does, and the state the app never had a display for.
    case awaitingIqamah(prayer: Prayer, adhan: Date, iqamah: Date)

    /// Inside a prayer's window, with the jamaah — where there is one — already past.
    case inWindow(prayer: Prayer, adhan: Date, closesAt: Date)

    /// All five logged as prayed. `next` is tomorrow's Fajr, or nil past the end of the
    /// cached timings.
    case dayComplete(next: PrayerEvent?)

    /// No timings loaded yet, or none covering now.
    case unavailable
}
