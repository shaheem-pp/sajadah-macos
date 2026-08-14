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

    func isComplete(_ dayKey: String) -> Bool {
        days[dayKey]?.isComplete ?? false
    }

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

    /// Consecutive complete days ending today. Today only counts once every prayer is logged,
    /// so a day still in progress doesn't look like a broken streak.
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
        // Walking the sorted list forward means only `previous` is ever needed to tell
        // whether a run continues.
        let complete = days.filter { $0.value.isComplete }.keys.sorted()
        var best = 0
        var run = 0
        var preceding: String?

        for key in complete {
            run = (preceding != nil && DayKey.previous(key) == preceding) ? run + 1 : 1
            best = max(best, run)
            preceding = key
        }
        return best
    }

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

    private var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = base.appendingPathComponent("Sajadah", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("prayer-log.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        days = (try? JSONDecoder().decode([String: DayLog].self, from: data)) ?? [:]
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
