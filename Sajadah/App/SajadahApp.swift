//
//  SajadahApp.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import AppKit
import SwiftUI

enum SajadahWindow {
    static let main = "main"
}

@main
struct SajadahApp: App {
    @State private var app = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .sajadahEnvironment(app)
        } label: {
            // Must be a lone `Image` — MenuBarExtra drops the text from anything richer.
            // `app.store.menuBar` already accounts for Iqamah — see PrayerTimesStore.tick(_:iqamah:log:).
            Image(nsImage: MenuBarLabelRenderer.image(for: app.store.menuBar))
        }
        .menuBarExtraStyle(.window)

        // `Window`, not `WindowGroup`: there is only ever one of this. A group opens a fresh
        // window every time `openWindow(id:)` is called, so clicking the popover's Quran
        // button twice — or tapping two widgets — left you with a stack of identical windows.
        // A single-instance scene brings the existing one forward instead.
        Window("Sajadah", id: SajadahWindow.main) {
            MainWindowView()
                .onOpenURL { url in
                    // Widget taps arrive as sajadah:// URLs; anything unrecognised just
                    // opens the app rather than doing nothing.
                    if let ref = SajadahLink.parse(url) {
                        app.navigation.open(ref)
                    } else {
                        app.navigation.openToday()
                    }
                }
                .sajadahEnvironment(app)
        }
        // Sajadah starts in the menubar; the window opens from the popover or the Dock icon
        // rather than appearing unbidden on every login.
        .defaultLaunchBehavior(.suppressed)
        // The app menu only exists while a window is open, and its stock Quit item took the
        // menubar item down with the window — the one thing someone pressing ⌘Q on a visitor
        // window did not mean. So ⌘Q sends the windows away and the item stays; the real quit
        // sits under ⌥⌘Q here and on the popover's own button. The Dock's Quit, logout and
        // shutdown never went through this item and still terminate.
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Return to Menu Bar") { Self.closeWindows() }
                    .keyboardShortcut("q", modifiers: .command)
                Button("Quit Sajadah") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .sajadahEnvironment(app)
        }
        // The view fixes its width and leaves height free; without this the window ignores
        // both and opens at the split view's minimum.
        .windowResizability(.contentSize)
    }

    /// Closes the main window and Settings — the same test `DockVisibility` uses for what
    /// counts as a window, so the Dock icon follows on its own. The popover is a panel and
    /// is left alone.
    private static func closeWindows() {
        for window in NSApp.windows where !(window is NSPanel) && window.isVisible && window.canBecomeMain {
            window.close()
        }
    }
}
