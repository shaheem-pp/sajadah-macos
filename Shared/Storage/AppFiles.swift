//
//  AppFiles.swift
//  Shared between Sajadah and SajadahWidgets
//

import Foundation

/// Resolves the app's data directory.
///
/// A widget runs in its own sandbox and cannot see the app's Application Support directory, so
/// everything the widget needs lives in a shared App Group container instead. If the group
/// container is unavailable — the entitlement missing, or the app running unsigned — this
/// falls back to Application Support so the app itself keeps working; only the widgets go
/// blank.
nonisolated enum AppFiles {

    /// macOS requires app group identifiers to be prefixed with the team ID, which is why
    /// this cannot simply be a literal: a fork signs with a different team and would have to
    /// edit source to build. Both targets instead declare it in their Info.plist as
    /// `$(TeamIdentifierPrefix)dev.shaheem.Sajadah`, which Xcode expands at build time from
    /// whatever `DEVELOPMENT_TEAM` is set to. The fallback only matters if that key goes
    /// missing, and even then the container lookup below degrades rather than crashing.
    static let appGroup: String = Bundle.main
        .object(forInfoDictionaryKey: "SajadahAppGroup") as? String
        ?? "853K3F2A4U.dev.shaheem.Sajadah"

    /// True when the shared container is reachable, which is what widgets depend on.
    static var usingSharedContainer: Bool { groupRoot != nil }

    private static var groupRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var fallbackRoot: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static var root: URL? {
        (groupRoot ?? fallbackRoot)?.appendingPathComponent("Sajadah", isDirectory: true)
    }

    static func url(for relativePath: String) -> URL? {
        guard let file = root?.appendingPathComponent(relativePath) else { return nil }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return file
    }

    /// Read-only lookup: never creates directories, so widgets don't churn the container.
    static func existingURL(for relativePath: String) -> URL? {
        guard let file = root?.appendingPathComponent(relativePath),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    static func removeDirectory(_ relativePath: String) {
        guard let url = root?.appendingPathComponent(relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Migration

    /// Moves data written before the App Group existed into the shared container.
    ///
    /// Called once at launch. Without this the user silently loses their prayer log and
    /// streak the first time they run a build that has widgets.
    static func migrateFromApplicationSupportIfNeeded() {
        guard let groupRoot, let fallbackRoot else { return }

        let old = fallbackRoot.appendingPathComponent("Sajadah", isDirectory: true)
        let new = groupRoot.appendingPathComponent("Sajadah", isDirectory: true)

        let manager = FileManager.default
        guard manager.fileExists(atPath: old.path) else { return }
        // Already migrated — the old directory is left alone rather than deleted, so a
        // downgrade to a pre-widget build still finds its data.
        guard !manager.fileExists(atPath: new.path) else { return }

        try? manager.createDirectory(at: groupRoot, withIntermediateDirectories: true)
        try? manager.copyItem(at: old, to: new)
    }
}
