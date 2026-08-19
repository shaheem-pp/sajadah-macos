//
//  PrayerLogStore.swift
//  Sajadah
//

import Foundation
import Observation

/// Records which prayers were prayed, and works out streaks.
///
/// Kept in its own file on disk, separate from the timings cache: this is the user's own data
/// and must survive a location change, a method change, or a cache wipe.
@Observable
final class PrayerLogStore {

    private(set) var days: [String: DayLog] = [:]

    /// Fires when an entry changes, so pending check-ins can be re-evaluated.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        load()
    }

    // MARK: Reading

    func state(for prayer: Prayer, on dayKey: String) -> PrayerLogState? {
        days[dayKey]?.state(for: prayer)
    }

    func isComplete(_ dayKey: String) -> Bool { days.isComplete(dayKey) }

    func prayedCount(on dayKey: String) -> Int {
        days[dayKey]?.prayed.count ?? 0
    }

    // MARK: Writing

    func set(_ state: PrayerLogState?, for prayer: Prayer, on dayKey: String) {
        guard prayer.isPrayer else { return }
        var day = days[dayKey] ?? DayLog()
        guard day.state(for: prayer) != state else { return }

        day.set(state, for: prayer)
        if day.prayed.isEmpty && day.missed.isEmpty {
            days.removeValue(forKey: dayKey)
        } else {
            days[dayKey] = day
        }

        save()
        onChange?()
    }

    /// Cycles unlogged → prayed → missed → unlogged, for tapping a row directly.
    func cycle(_ prayer: Prayer, on dayKey: String) {
        let next: PrayerLogState? = switch state(for: prayer, on: dayKey) {
        case nil: .prayed
        case .prayed: .missed
        case .missed: nil
        }
        set(next, for: prayer, on: dayKey)
    }

    // MARK: Streaks

    func currentStreak(asOf todayKey: String) -> Int { days.currentStreak(asOf: todayKey) }

    var bestStreak: Int { days.bestStreak }

    /// Most recent `count` days, oldest first, for the history grid.
    func recentDays(endingAt todayKey: String, count: Int) -> [(dayKey: String, log: DayLog?)] {
        var keys: [String] = []
        var cursor: String? = todayKey
        for _ in 0..<count {
            guard let key = cursor else { break }
            keys.append(key)
            cursor = DayKey.previous(key)
        }
        return keys.reversed().map { ($0, days[$0]) }
    }

    // MARK: Persistence

    private var fileURL: URL? { AppFiles.url(for: CacheFileName.prayerLog) }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        days = (try? JSONDecoder().decode([String: DayLog].self, from: data)) ?? [:]
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
