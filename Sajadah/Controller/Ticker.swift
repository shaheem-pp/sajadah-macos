//
//  Ticker.swift
//  Sajadah
//

import Foundation

/// Drives the countdown. One second is plenty — the store already suppresses menubar
/// redraws when the rendered text hasn't changed.
///
/// This is an async loop rather than a `Timer` on purpose: a run-loop timer in the default
/// mode stops firing while a menu is being tracked, which is exactly when the countdown is on
/// screen. `Task.sleep` is not tied to the run loop, so it keeps ticking with the popover open.
@MainActor
final class Ticker {
    private var task: Task<Void, Never>?
    private let onTick: (Date) -> Void

    init(onTick: @escaping (Date) -> Void) {
        self.onTick = onTick
    }

    func start() {
        stop()
        onTick(.now)
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                // Recomputed from `.now` every tick, so sleep drift never accumulates.
                onTick(.now)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
