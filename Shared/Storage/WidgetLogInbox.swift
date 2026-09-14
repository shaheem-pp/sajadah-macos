//
//  WidgetLogInbox.swift
//  Shared between Sajadah and SajadahWidgets
//

import Foundation

/// One tap on a widget's prayer button, waiting for the app to fold it into the log.
nonisolated struct WidgetLogEntry: Codable, Sendable, Equatable {
    let id: UUID
    let dayKey: String
    let prayer: Prayer
    /// Nil clears the entry — a second tap on a prayer already marked prayed.
    let state: PrayerLogState?
    let at: Date
}

/// How a prayer logged from a widget reaches the app.
///
/// The widget extension cannot write the log itself. On the builds people download it can't
/// even read the App Group container (see `AppFiles`), and if it wrote a copy of the log into
/// its own container the app would never look there for one. So a tap becomes one small file
/// in a directory the extension can always write and the app can always read — its own
/// container, which the app already reaches to mirror the cache — and the app folds those
/// files into the real log and deletes them.
///
/// One file per tap rather than one file appended to: two processes editing a single file
/// would need coordination, and a directory of independent files needs none. The widget lays
/// pending taps over the log it reads, so a tap shows immediately, before the app has run.
nonisolated enum WidgetLogInbox {
    static let directoryName = "widget-log-inbox"

    // MARK: Widget side

    /// Records a tap. Best effort: if the container isn't writable there is nothing the widget
    /// can do about it, and the button will simply appear not to have taken.
    static func append(_ entry: WidgetLogEntry) {
        guard let directory = AppFiles.widgetInboxURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: directory.appendingPathComponent("\(entry.id.uuidString).json"), options: .atomic)
    }

    /// Every tap not yet folded in, oldest first, so applying them in order gives last-tap-wins.
    static func pending() -> [WidgetLogEntry] {
        guard let directory = AppFiles.widgetInboxURL,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> WidgetLogEntry? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(WidgetLogEntry.self, from: data)
            }
            .sorted { $0.at < $1.at }
    }

    /// Lays pending taps over a log read from disk — what the widget shows until the app runs.
    static func apply(_ entries: [WidgetLogEntry], to log: inout [String: DayLog]) {
        for entry in entries {
            var day = log[entry.dayKey] ?? DayLog()
            day.set(entry.state, for: entry.prayer)
            if day.prayed.isEmpty && day.missed.isEmpty {
                log.removeValue(forKey: entry.dayKey)
            } else {
                log[entry.dayKey] = day
            }
        }
    }

    // MARK: App side

    /// Deletes the files for taps the app has folded in. Only those — a tap that lands between
    /// the app's read and this call is left for the next pass rather than lost.
    static func remove(_ entries: [WidgetLogEntry]) {
        guard let directory = AppFiles.widgetInboxURL else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(entry.id.uuidString).json"))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
