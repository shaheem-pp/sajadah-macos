//
//  Ticker.swift
//  Sajadah
//

import AppKit
import Foundation

/// Drives the countdown, at whichever rate is actually being looked at.
///
/// A second is what the popover and window need — their countdowns show seconds. The menubar
/// does not: it reads "5h 9m", so it can only change once a minute, and Sajadah is in that
/// state almost all of the time. Ticking every second regardless meant waking the CPU sixty
/// times a minute, for ever, to recompute a string that hadn't changed.
///
/// So the interval follows the audience: one second while something with a live countdown is
/// on screen, otherwise one wake a minute, timed to land on the exact instant the menubar's
/// minute figure changes.
///
/// This is an async loop rather than a `Timer` on purpose: a run-loop timer in the default
/// mode stops firing while a menu is being tracked, which is exactly when the countdown is on
/// screen. `Task.sleep` is not tied to the run loop, so it keeps ticking with the popover open.
@MainActor
final class Ticker {
    private var task: Task<Void, Never>?
    private let onTick: (Date) -> Void
    private let countdownTarget: () -> Date?

    /// - Parameter countdownTarget: the instant the menubar is counting down to, if any. Used
    ///   only to work out when its minute figure next changes.
    init(countdownTarget: @escaping () -> Date? = { nil }, onTick: @escaping (Date) -> Void) {
        self.countdownTarget = countdownTarget
        self.onTick = onTick
    }

    func start() {
        observeWake()
        run()
    }

    private func run() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Recomputed from `.now` every tick, so sleep drift never accumulates.
                onTick(.now)

                let interval = idleInterval(at: .now)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Restarts the loop when something appears on screen.
    ///
    /// Without this the idle cadence would be sticky: open the popover a second after a
    /// minute-long sleep began and its seconds countdown would sit frozen until that sleep
    /// ended. Restarting re-evaluates the interval immediately, and ticks once on the way.
    private func observeWake() {
        guard !isObserving else { return }
        isObserving = true

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSApplication.didBecomeActiveNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.run() }
            }
        }
    }

    private var isObserving = false

    func stop() {
        task?.cancel()
        task = nil
    }

    /// A second when a live countdown is on screen. Otherwise: exactly as long as it takes for
    /// the menubar's minute figure to change.
    ///
    /// Sleeping to the next *wall-clock* minute would be wrong. "5h 9m" counts whole minutes
    /// remaining until a prayer, and a prayer is not at :00 — a prayer at 13:00:30 flips the
    /// display at :30 past each minute. Waking on the wall clock would leave the menubar up to
    /// a minute stale. The remainder below lands on the flip itself, so the reading is exact
    /// and it still only costs one wake a minute.
    private func idleInterval(at date: Date) -> Double {
        guard !Self.hasVisibleCountdown else { return 1 }

        guard let target = countdownTarget() else { return 60 }
        let remaining = target.timeIntervalSince(date)
        guard remaining > 0 else { return 1 }

        let untilFlip = remaining.truncatingRemainder(dividingBy: 60)
        // A remainder of ~0 means we just woke on the flip; the next one is a full minute out.
        return untilFlip < 0.5 ? 60 : untilFlip
    }

    /// Whether anything showing a per-second countdown is on screen.
    ///
    /// Two signals, because neither covers both cases:
    ///
    ///  - **The app being active.** This is what catches the menubar popover, which is where
    ///    the seconds countdown mostly lives. There is no dependable way to pick that panel
    ///    out of `NSApp.windows` — SwiftUI keeps hosting windows around that report
    ///    `isVisible` and even a visible occlusion state with nothing on screen at all, which
    ///    is what made an earlier version of this tick every second forever.
    ///  - **A main window existing.** The main window shows a countdown too, and should keep
    ///    running while the user is in another app looking at it.
    private static var hasVisibleCountdown: Bool {
        guard let app = NSApp else { return false }
        if app.isActive { return true }
        return app.windows.contains { !($0 is NSPanel) && $0.canBecomeMain && $0.isVisible }
    }
}
