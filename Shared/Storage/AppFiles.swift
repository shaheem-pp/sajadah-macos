//
//  AppFiles.swift
//  Shared between Sajadah and SajadahWidgets
//

import Darwin
import Foundation

/// Resolves where Sajadah's data lives, on both sides of the app/widget divide.
///
/// The obvious answer is an App Group container, and on a properly signed build that is
/// exactly what happens. It does not work on the builds people download, though, and the
/// reason is worth writing down because it looks like a bug in the widget code and isn't:
///
///  - Releases are ad-hoc signed. Without an Apple Developer Program membership there is no
///    Developer ID certificate, and an ad-hoc signature carries no team identifier.
///  - macOS grants App Group containers by matching the group against the signature's team.
///    The *app* is granted one anyway; a sandboxed *extension* is not, and the kernel denies
///    every read: `System Policy: SajadahWidgets deny(1) file-read-data …/Group Containers/…`.
///  - The extension cannot opt out of the sandbox to get around that. PlugInKit refuses to
///    load it at all: `Ignoring mis-configured plugin: plug-ins must be sandboxed`.
///
/// What a sandboxed extension can always read, with no entitlement and no team identifier, is
/// its *own* container. So the app mirrors the handful of files widgets need into the widget
/// extension's container, and the widget reads whichever copy it can actually get at. Signed
/// builds keep using the App Group and never touch the mirror.
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

    /// The widget extension's bundle identifier, whose container holds the mirror. Derived
    /// from the app's own identifier so a fork that renames the bundle still matches, and
    /// declared in both targets' Info.plist for the same reason `appGroup` is.
    static let widgetBundleID: String = Bundle.main
        .object(forInfoDictionaryKey: "SajadahWidgetBundleID") as? String
        ?? "dev.shaheem.Sajadah.SajadahWidgets"

    /// The files widgets read, and so the only ones worth mirroring. Everything else — surah
    /// text, reading position — is the app's own business.
    static let mirroredFiles: Set<String> = [
        CacheFileName.prayerTimes,
        CacheFileName.prayerLog,
        CacheFileName.dailyAyah,
        CacheFileName.iqamah,
    ]

    /// True when the shared container is reachable, which is what widgets depend on.
    static var usingSharedContainer: Bool { sharedRoot != nil }

    // MARK: Roots

    /// The user's real home directory.
    ///
    /// `NSHomeDirectory()` is the sandbox container for a sandboxed process — for Sajadah,
    /// `/Users/…/Library/Containers/dev.shaheem.Sajadah/Data` — and the cross-process paths
    /// below are not relative to that. Deriving the real home by cutting the container suffix
    /// off is exact and needs no entitlement; `getpwuid` is the fallback, and is checked for
    /// the same rewriting rather than trusted.
    private static var realHome: URL {
        let sandboxed = NSHomeDirectory()
        if let containers = sandboxed.range(of: "/Library/Containers/") {
            return URL(fileURLWithPath: String(sandboxed[..<containers.lowerBound]), isDirectory: true)
        }
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            let path = String(cString: directory)
            if !path.contains("/Library/Containers/") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return URL(fileURLWithPath: sandboxed, isDirectory: true)
    }

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

    /// The widget extension's own Application Support directory, addressed from outside it.
    ///
    /// Not gated on the container already existing. The obvious guard — stat the container
    /// first and skip if it's missing — is itself a sandboxed read, so a denial there is
    /// indistinguishable from "no container yet" and silently turns the mirror off for good.
    /// Writing is the honest test: it either lands or it doesn't.
    private static var widgetMirrorRoot: URL {
        realHome
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
    }

    private static var sharedRoot: URL? { groupRoot }

    /// Where this process writes its own copy.
    private static var root: URL? {
        (sharedRoot ?? fallbackRoot)?.appendingPathComponent("Sajadah", isDirectory: true)
    }

    /// True when this is the widget extension rather than the app.
    private static var isWidgetExtension: Bool {
        Bundle.main.bundleIdentifier == widgetBundleID
    }

    /// Every place a file might be readable from, best first.
    ///
    /// Order matters, and not only for correctness. The extension looks in its own container
    /// first: the App Group path resolves perfectly well there right up until the kernel
    /// refuses the read, so leading with it would mean a logged sandbox violation on every
    /// timeline reload, forever, on every unsigned copy. The app leads with the App Group,
    /// which is its own canonical store and the one it writes.
    private static var readRoots: [URL] {
        let ordered: [URL?] = isWidgetExtension
            ? [fallbackRoot, groupRoot]
            : [groupRoot, widgetMirrorRoot, fallbackRoot]

        var roots: [URL] = []
        for candidate in ordered {
            guard let candidate else { continue }
            let root = candidate.appendingPathComponent("Sajadah", isDirectory: true)
            if !roots.contains(root) { roots.append(root) }
        }
        return roots
    }

    /// Where widget taps queue for the app — see `WidgetLogInbox`. The same directory from
    /// both sides: the extension's own Application Support, which it addresses as its home
    /// and the app addresses through the container path it already mirrors into.
    static var widgetInboxURL: URL? {
        let root = isWidgetExtension ? fallbackRoot : widgetMirrorRoot
        return root?
            .appendingPathComponent("Sajadah", isDirectory: true)
            .appendingPathComponent(WidgetLogInbox.directoryName, isDirectory: true)
    }

    // MARK: Reading

    /// The first copy of `relativePath` this process can actually read.
    ///
    /// Deliberately an attempted read rather than an `isReadable` check: a sandbox denial is
    /// what we are detecting, and the cheap answers (the file exists, the path resolves) are
    /// both yes in exactly the case that fails.
    static func readData(for relativePath: String) -> Data? {
        for root in readRoots {
            if let data = try? Data(contentsOf: root.appendingPathComponent(relativePath)) {
                return data
            }
        }
        return nil
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
        for root in readRoots {
            let file = root.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    // MARK: Writing

    /// Writes `data`, and mirrors it to the widget extension's container when widgets read it.
    ///
    /// The mirror is best-effort by design. It needs the extension's container to exist and,
    /// from the sandboxed app, a temporary-exception entitlement to write into it; if either
    /// is missing this quietly does the primary write only, which is the pre-mirror behaviour.
    static func write(_ data: Data, to relativePath: String) {
        if let url = url(for: relativePath) {
            try? data.write(to: url, options: .atomic)
        }
        guard mirroredFiles.contains(relativePath) else { return }
        mirror(data, to: relativePath)
    }

    /// Re-mirrors everything widgets read.
    ///
    /// Called at launch, because the usual trigger is a cache write and a Mac that already has
    /// today's timings won't do one — leaving a freshly created widget container empty until
    /// something changed. Cheap: four small files.
    static func refreshWidgetMirror() {
        for name in mirroredFiles {
            guard let source = root?.appendingPathComponent(name),
                  let data = try? Data(contentsOf: source) else { continue }
            mirror(data, to: name)
        }
    }

    private static func mirror(_ data: Data, to relativePath: String) {
        let file = widgetMirrorRoot
            .appendingPathComponent("Sajadah", isDirectory: true)
            .appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Removing

    /// Removes a file from the primary location and the mirror both, so a cleared cache does
    /// not linger in the widget.
    static func remove(_ relativePath: String) {
        let manager = FileManager.default
        if let url = root?.appendingPathComponent(relativePath) {
            try? manager.removeItem(at: url)
        }
        try? manager.removeItem(
            at: widgetMirrorRoot
                .appendingPathComponent("Sajadah", isDirectory: true)
                .appendingPathComponent(relativePath)
        )
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
        guard let sharedRoot, let fallbackRoot else { return }

        let old = fallbackRoot.appendingPathComponent("Sajadah", isDirectory: true)
        let new = sharedRoot.appendingPathComponent("Sajadah", isDirectory: true)

        let manager = FileManager.default
        guard manager.fileExists(atPath: old.path) else { return }
        // Already migrated — the old directory is left alone rather than deleted, so a
        // downgrade to a pre-widget build still finds its data.
        guard !manager.fileExists(atPath: new.path) else { return }

        try? manager.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
        try? manager.copyItem(at: old, to: new)
    }
}
