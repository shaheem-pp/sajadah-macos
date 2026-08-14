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
                .environment(app.location)
                .environment(app.settings)
                .environment(app.store)
                .environment(app.log)
                .environment(app.scheduler)
        } label: {
            // Must be a lone `Image` — MenuBarExtra drops the text from anything richer.
            Image(nsImage: MenuBarLabelRenderer.image(for: app.store.menuBar))
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: SajadahWindow.main) {
            AppView()
                .environment(app.location)
                .environment(app.settings)
                .environment(app.store)
                .environment(app.log)
                .environment(app.scheduler)
        }
        // Sajadah starts in the menubar; the window opens from the popover or the Dock icon
        // rather than appearing unbidden on every login.
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(app.location)
                .environment(app.settings)
                .environment(app.store)
                .environment(app.log)
                .environment(app.scheduler)
        }
    }
}
