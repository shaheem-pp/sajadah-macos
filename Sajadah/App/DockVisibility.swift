//
//  DockVisibility.swift
//  Sajadah
//

import AppKit

/// Keeps the Dock icon in step with whether Sajadah actually has a window open.
///
/// Sajadah lives in the menubar, and for almost all of its life it has nothing on screen — a
/// Dock icon for that is just clutter. But a permanent `LSUIElement` is the wrong answer too:
/// with no Dock presence the main window can't be reached by ⌘-Tab and the app gets no menu
/// bar, which the Quran reader wants for Edit → Copy and ⌘W.
///
/// So the policy follows the windows. Accessory while only the menubar is showing, regular the
/// moment a real window opens, back to accessory when the last one closes.
@MainActor
enum DockVisibility {

    /// Windows that don't count: the menubar popover, and any other panel macOS puts up. A
    /// panel on screen is not a reason to occupy the Dock.
    private static func isRealWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        // MenuBarExtra's own hosting window reports no title and never becomes main.
        return window.isVisible && window.canBecomeMain
    }

    /// Applies the policy for the current window state. Cheap and idempotent, so it is safe to
    /// call from every window notification.
    ///
    /// `closing` is the window a `willCloseNotification` is about, and is discounted. That
    /// notification fires *before* the window goes away, so without naming it the count would
    /// still include it and the Dock icon would never go back down — and relying on a deferred
    /// re-count instead would be a race against AppKit finishing the close.
    ///
    /// `NSApp` is an implicitly-unwrapped optional and really is nil early on — `App.init()`
    /// runs before SwiftUI has made the application object — so it is bound rather than
    /// assumed. There is nothing to decide before there is an app, anyway.
    static func update(closing: NSWindow? = nil) {
        guard let app = NSApp else { return }

        let wanted: NSApplication.ActivationPolicy = app.windows
            .contains { $0 !== closing && isRealWindow($0) } ? .regular : .accessory
        guard app.activationPolicy() != wanted else { return }
        app.setActivationPolicy(wanted)

        // Switching to regular mid-session leaves the app behind whatever was in front, which
        // reads as the window having failed to open.
        if wanted == .regular {
            app.activate(ignoringOtherApps: true)
        }
    }

    /// Starts watching.
    ///
    /// Updates are deferred by a turn of the main actor, which is what lets this be called
    /// from `AppCoordinator.init()` — before `NSApp` exists at all.
    static func start() {
        let center = NotificationCenter.default
        let appeared: [Notification.Name] = [
            NSApplication.didFinishLaunchingNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
        ]
        for name in appeared {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in update() }
            }
        }

        center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            let closing = note.object as? NSWindow
            Task { @MainActor in update(closing: closing) }
        }

        Task { @MainActor in update() }
    }
}
