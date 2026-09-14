//
//  SajadahProvider.swift
//  SajadahWidgets
//

import WidgetKit

struct SajadahEntry: TimelineEntry {
    let date: Date
    let snapshot: SajadahSnapshot

    static let placeholder = SajadahEntry(date: .now, snapshot: SajadahSnapshot())
}

/// Feeds every Sajadah widget.
///
/// Widgets never hit the network — the app keeps the shared cache fresh and this reads it.
/// That keeps them working offline and costs no refresh budget.
struct SajadahProvider: TimelineProvider {

    func placeholder(in context: Context) -> SajadahEntry {
        SajadahEntry(date: .now, snapshot: SajadahSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (SajadahEntry) -> Void) {
        completion(SajadahEntry(date: .now, snapshot: SajadahSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SajadahEntry>) -> Void) {
        let now = Date.now
        let snapshot = SajadahSnapshot.load()

        // One entry now, then one at every instant the widgets' wording changes, so each
        // flips exactly on its boundary. The countdown itself needs no entries —
        // `Text(timerInterval:)` ticks on its own — so this stays to a few dozen at most
        // rather than one a minute.
        let horizon = now.addingTimeInterval(36 * 3600)
        let dates = Self.boundaries(in: snapshot, after: now, until: horizon)
        let entries = ([now] + dates).map { SajadahEntry(date: $0, snapshot: snapshot) }

        // Re-read the cache after the last boundary, or in an hour if there's no data yet
        // (the app may not have fetched anything the first time a widget is placed).
        let refresh = dates.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    /// Every instant between `start` and `end` at which some widget says something different:
    /// each Adhan, each Iqamah and the quarter-hour before it, each Isha cutoff, and each
    /// midnight — when the log the ring is drawn from becomes a new day's.
    static func boundaries(in snapshot: SajadahSnapshot, after start: Date, until end: Date) -> [Date] {
        var dates: Set<Date> = []

        for event in snapshot.events where event.prayer.isPrayer {
            dates.insert(event.date)
            if let iqamah = snapshot.iqamahDate(for: event) {
                dates.insert(iqamah)
                dates.insert(iqamah.addingTimeInterval(-15 * 60))
            }
        }

        for day in snapshot.days.values {
            if let cutoff = day.windowClose(for: .isha, ishaCutoffMinutes: snapshot.ishaCutoffMinutes) {
                dates.insert(cutoff)
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = day.timeZone
            if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day.dhuhr)) {
                dates.insert(midnight)
            }
        }

        return dates.filter { $0 > start && $0 <= end }.sorted()
    }
}
