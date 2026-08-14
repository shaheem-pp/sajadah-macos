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
