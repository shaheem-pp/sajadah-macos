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

        // One entry now, then one at each upcoming prayer so "next prayer" flips exactly on
        // the boundary. The countdown itself needs no entries — `Text(_:style:)` ticks on its
        // own — so this stays to a handful rather than one a minute.
        var dates: [Date] = [now]
        dates += snapshot.events
            .filter { $0.date > now && $0.prayer.isPrayer }
            .prefix(8)
            .map(\.date)

        let entries = dates.map { SajadahEntry(date: $0, snapshot: snapshot) }

        // Re-read the cache after the last known prayer, or in an hour if there's no data yet
        // (the app may not have fetched anything the first time a widget is placed).
        let refresh = dates.last.map { $0.addingTimeInterval(60) }
            ?? now.addingTimeInterval(3600)

        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}
