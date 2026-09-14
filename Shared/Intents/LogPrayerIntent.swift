//
//  LogPrayerIntent.swift
//  Shared between Sajadah and SajadahWidgets
//

import AppIntents
import Foundation

/// Marks a prayer prayed from a widget button, or clears it on a second tap.
///
/// Runs inside the widget extension, which can't reach the app's log, so the tap is queued
/// for the app through `WidgetLogInbox` rather than written directly. Compiled into both
/// targets: WidgetKit resolves the intent in the extension, and the app has to know the type
/// to be a valid host for it.
struct LogPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Prayer"
    static let description = IntentDescription("Marks a prayer as prayed in Sajadah.")
    /// A button's intent, not a Shortcuts action: it only makes sense with a widget's day.
    static let isDiscoverable = false

    @Parameter(title: "Prayer")
    var prayer: String

    /// The civil day the widget was drawn for, so a tap after midnight on a widget that still
    /// shows yesterday's ring logs yesterday's prayer rather than today's.
    @Parameter(title: "Day")
    var dayKey: String

    init() {
        prayer = Prayer.fajr.rawValue
        dayKey = ""
    }

    init(prayer: Prayer, dayKey: String) {
        self.prayer = prayer.rawValue
        self.dayKey = dayKey
    }

    func perform() async throws -> some IntentResult {
        guard let prayer = Prayer(rawValue: prayer), prayer.isPrayer else { return .result() }

        // The app's rule: a prayer can be logged only once its time has come. The button is
        // disabled before that, but the check belongs with the write, not the drawing.
        let snapshot = SajadahSnapshot.load()
        guard let day = snapshot.days[dayKey], day.time(for: prayer) <= .now else { return .result() }

        let current = snapshot.log[dayKey]?.state(for: prayer)
        let next: PrayerLogState? = current == .prayed ? nil : .prayed
        WidgetLogInbox.append(WidgetLogEntry(id: UUID(), dayKey: dayKey, prayer: prayer, state: next, at: .now))
        return .result()
    }
}
