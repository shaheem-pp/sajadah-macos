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

// MARK: - Resolving

nonisolated extension DayPhase {

    /// Works out the phase from the raw pieces, so the app's store and the widget snapshot
    /// can't each decide differently — the widget has no store, only the cache on disk.
    ///
    /// - Parameters:
    ///   - events: every known timing, sorted, across every cached day.
    ///   - days: the cached days, keyed by `DayKey`, for looking up window closes.
    ///   - iqamah: the masjid's posted times, if any — nil means no jamaah phase ever.
    ///   - ishaCutoffMinutes: when Isha's window closes, as minutes from midnight.
    static func resolve(
        at now: Date,
        events: [PrayerEvent],
        days: [String: DayTimings],
        timeZone: TimeZone,
        iqamah: IqamahTimes?,
        ishaCutoffMinutes: Int,
        dayIsComplete: Bool
    ) -> DayPhase {
        guard !events.isEmpty else { return .unavailable }

        let next = events.first { $0.date > now && $0.prayer.isPrayer }
        let current = events.last { $0.date <= now && $0.prayer.isPrayer }

        // An answered day outranks everything else. It can't be reached early: a prayer is
        // only loggable once its own time has come.
        if dayIsComplete { return .dayComplete(next: next) }

        if let current,
           let iqamahDate = iqamah?.date(for: current.prayer, onSameDayAs: current.date, timeZone: timeZone),
           now < iqamahDate {
            return .awaitingIqamah(prayer: current.prayer, adhan: current.date, iqamah: iqamahDate)
        }

        // `current` can belong to yesterday — at 3am it's yesterday's Isha — which is exactly
        // why the window close is looked up on that event's own day rather than today's.
        if let current,
           let day = days[DayKey.make(for: current.date, in: timeZone)],
           let close = day.windowClose(for: current.prayer, ishaCutoffMinutes: ishaCutoffMinutes),
           now < close {
            return .inWindow(prayer: current.prayer, adhan: current.date, closesAt: close)
        }

        return next.map { .awaitingAdhan(next: $0) } ?? .unavailable
    }

    /// The prayer whose hour the display is washed in. A finished day sits in Isha's night
    /// whatever comes next — the day being over is the message, not that Fajr is coming.
    var prayer: Prayer? {
        switch self {
        case .awaitingAdhan(let next): next.prayer
        case .awaitingIqamah(let prayer, _, _), .inWindow(let prayer, _, _): prayer
        case .dayComplete: .isha
        case .unavailable: nil
        }
    }

    /// The instant the phase is counting towards, if there is one.
    var target: Date? {
        switch self {
        case .awaitingAdhan(let next): next.date
        case .awaitingIqamah(_, _, let iqamah): iqamah
        case .inWindow(_, _, let closesAt): closesAt
        case .dayComplete(let next): next?.date
        case .unavailable: nil
        }
    }

    /// How far the phase's own span has run, 0...1 — from Adhan to Iqamah, or from Adhan to
    /// the window's close. Nil where there is nothing named to measure from.
    func progress(at now: Date) -> Double? {
        switch self {
        case .awaitingIqamah(_, let adhan, let iqamah): Self.fraction(from: adhan, to: iqamah, at: now)
        case .inWindow(_, let adhan, let closesAt): Self.fraction(from: adhan, to: closesAt, at: now)
        case .awaitingAdhan, .dayComplete, .unavailable: nil
        }
    }

    /// Clamped. Nil for a span with no width, which at extreme latitudes is a real possibility
    /// rather than a defensive guard.
    static func fraction(from start: Date, to end: Date, at now: Date) -> Double? {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return nil }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }
}
