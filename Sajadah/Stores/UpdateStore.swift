//
//  UpdateStore.swift
//  Sajadah
//

import AppKit
import Foundation
import Observation

/// Whether a newer release exists, and how recently that was established.
///
/// Follows the same shape as the other stores — cache to disk, keep showing what's cached,
/// and stay quiet when a refresh fails. Quiet matters more here than anywhere else: a failed
/// update check is not news, and an app that reports one is an app that nags.
@MainActor
@Observable
final class UpdateStore {

    /// How long a result stands before another check is worth making.
    ///
    /// Once a day. Unauthenticated GitHub allows 60 calls an hour per IP, so this is free and
    /// needs no token — which in turn means no secret shipped inside a public app.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    // MARK: Observed state

    /// The newest release, when it is genuinely newer than this build and the user hasn't
    /// dismissed it. `nil` covers up-to-date, undecided and dismissed alike, because the UI
    /// treats all three the same way: show nothing.
    var available: ReleaseInfo? {
        guard let latest, let version = latest.version, version > currentVersion else { return nil }
        guard latest.tag != dismissedTag else { return nil }
        return latest
    }

    /// True once a check has found a newer release, whether or not it was dismissed — Settings
    /// still names the version when the popover has been told to stop mentioning it.
    var latest: ReleaseInfo?

    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    /// Surfaced in Settings only, and only after a check the user asked for.
    private(set) var lastError: String?

    let currentVersion = AppVersion.current

    // MARK: Private state

    @ObservationIgnored private let checker = UpdateChecker.shared
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var dismissedTag: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        loadFromDisk()
    }

    func configure(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Checking

    /// Checks only if the last result has gone stale and the user hasn't turned this off.
    ///
    /// Called at launch and on every tick. The tick is what covers a Mac left running for a
    /// month: launch-only would mean such a Mac never notices a release at all, and the guards
    /// below are two comparisons, so asking every second costs nothing.
    func checkIfDue() {
        guard settings?.updateChecksEnabled ?? true else { return }
        guard !isChecking else { return }
        if let lastCheckedAt, Date.now.timeIntervalSince(lastCheckedAt) < Self.checkInterval {
            return
        }
        check(userInitiated: false)
    }

    /// Checks now, whatever the schedule says. Reports failures, unlike the scheduled path.
    func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        task?.cancel()
        isChecking = true
        if userInitiated { lastError = nil }

        task = Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false }
            do {
                let release = try await checker.latest()
                guard !Task.isCancelled else { return }
                latest = release
                lastCheckedAt = .now
                lastError = nil
                writeToDisk()
            } catch {
                guard !Task.isCancelled else { return }
                // A scheduled check that fails leaves no trace: the network being down is not
                // something to tell someone about while they are looking at prayer times. It
                // also deliberately does not stamp `lastCheckedAt`, so the next tick retries
                // rather than waiting out the full day.
                if userInitiated {
                    lastError = (error as? UpdateError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: Acting

    /// Stops mentioning this particular release in the popover. A later one asks again.
    func dismissAvailable() {
        guard let latest else { return }
        dismissedTag = latest.tag
        writeToDisk()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(available?.pageURL ?? UpdateChecker.releasesPageURL)
    }

    /// Puts the upgrade command on the clipboard.
    ///
    /// The honest action for an ad-hoc signed app: it cannot replace itself in place, so the
    /// most it can usefully do is hand over the command that can.
    func copyUpdateCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(UpdateChecker.updateCommand, forType: .string)
    }

    // MARK: Persistence

    private struct Cache: Codable {
        var lastCheckedAt: Date?
        var latest: ReleaseInfo?
        var dismissedTag: String?
    }

    private func loadFromDisk() {
        guard let data = AppFiles.readData(for: CacheFileName.updateCheck),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        lastCheckedAt = cache.lastCheckedAt
        latest = cache.latest
        dismissedTag = cache.dismissedTag
    }

    private func writeToDisk() {
        let cache = Cache(lastCheckedAt: lastCheckedAt, latest: latest, dismissedTag: dismissedTag)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        AppFiles.write(data, to: CacheFileName.updateCheck)
    }
}
