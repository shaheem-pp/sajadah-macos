//
//  SajadahApp.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

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
            // `app.store.menuBar` already accounts for Iqamah — see PrayerTimesStore.tick(_:iqamah:).
            Image(nsImage: MenuBarLabelRenderer.image(for: app.store.menuBar))
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: SajadahWindow.main) {
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

        Settings {
            SettingsView()
                .sajadahEnvironment(app)
        }
    }
}
