//
//  PrayerLog.swift
//  Sajadah
//

import Foundation

/// Whether a prayer was prayed. "Unlogged" is the absence of a value rather than a case here,
/// because it means "not answered yet" — which is different from an answered "missed".
nonisolated enum PrayerLogState: String, Codable, Sendable {
    case prayed
    case missed

    var systemImage: String {
        switch self {
        case .prayed: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        }
    }
}

/// A pending "did you pray this?" question, anchored to the moment the prayer's window closes.
nonisolated struct PrayerCheckIn: Identifiable, Sendable, Equatable {
    let prayer: Prayer
    let dayKey: String
    let windowClose: Date

    var id: String { "\(dayKey)-\(prayer.rawValue)" }
}

/// One day's answers.
nonisolated struct DayLog: Codable, Sendable, Equatable {
    var prayed: Set<Prayer> = []
    var missed: Set<Prayer> = []

    /// The five obligatory prayers — sunrise is never tracked.
    static let tracked: [Prayer] = Prayer.allCases.filter(\.isPrayer)

    var isComplete: Bool {
        Self.tracked.allSatisfy(prayed.contains)
    }

    func state(for prayer: Prayer) -> PrayerLogState? {
        if prayed.contains(prayer) { return .prayed }
        if missed.contains(prayer) { return .missed }
        return nil
    }

    mutating func set(_ state: PrayerLogState?, for prayer: Prayer) {
        prayed.remove(prayer)
        missed.remove(prayer)
        switch state {
        case .prayed: prayed.insert(prayer)
        case .missed: missed.insert(prayer)
        case nil: break
        }
    }
}

// MARK: - Streaks

/// Streak maths on the raw log. Lives here rather than in the store so the widget extension
/// can compute the same numbers without pulling in the whole app.
///
/// Explicitly `nonisolated`: this module defaults to `MainActor` isolation, and widget
/// timeline providers call these off the main actor.
nonisolated extension Dictionary where Key == String, Value == DayLog {

    func isComplete(_ dayKey: String) -> Bool {
        self[dayKey]?.isComplete ?? false
    }

    /// Consecutive complete days ending today. Today only counts once every prayer is logged,
    /// so a day still in progress doesn't read as a broken streak.
    func currentStreak(asOf todayKey: String) -> Int {
        var key = todayKey
        if !isComplete(key) {
            guard let yesterday = DayKey.previous(key) else { return 0 }
            key = yesterday
        }

        var streak = 0
        while isComplete(key) {
            streak += 1
            guard let previous = DayKey.previous(key) else { break }
            key = previous
        }
        return streak
    }

    var bestStreak: Int {
        // Day keys are zero-padded `yyyy-MM-dd`, so a plain string sort is chronological.
        // Walking forward means only `previous` is ever needed to tell whether a run continues.
        let complete = filter(\.value.isComplete).keys.sorted()
        var best = 0
        var run = 0
        var preceding: String?

        for key in complete {
            run = (preceding != nil && DayKey.previous(key) == preceding) ? run + 1 : 1
            // Qualified: inside a Dictionary extension, bare `max` is `Sequence.max`.
            best = Swift.max(best, run)
            preceding = key
        }
        return best
    }
}
