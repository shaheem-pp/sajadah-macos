//
//  SettingsView.swift
//  Sajadah
//

import SwiftUI

/// Sidebar and detail, in the shape System Settings uses. A toolbar of tabs topped out at five:
/// a sixth icon no longer fit the 460pt window, and a row of glyphs gives nothing to scan once
/// you've forgotten which one is which.
///
/// Hand-rolled rather than `TabView(.sidebarAdaptable)`: the adaptable style synthesises its
/// own split view and offers no handle on the sidebar-toggle it adds or the column width it
/// picks, both of which are wrong for a Settings window.
struct SettingsView: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Non-optional selection, so a click on empty sidebar can't blank the detail.
            List(selection: $navigation.settingsPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 200)
            // Has to sit on the sidebar's own content — that is the column the toggle belongs
            // to, and the only place removing it takes effect.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane(navigation.settingsPane)
                .navigationTitle(navigation.settingsPane.title)
        }
        // Width fixed: the forms were laid out for 460pt and the sidebar adds the rest. Height
        // free, so the long Notifications pane can grow rather than scroll.
        .frame(minWidth: 680, maxWidth: 680, minHeight: 480, idealHeight: 560, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .notifications: NotificationSettingsView()
        case .fasting: FastingSettingsView()
        case .quran: QuranSettingsView()
        case .location: LocationSettingsView()
        case .masjid: MasjidSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

extension SettingsPane {
    var title: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .fasting: "Fasting"
        case .quran: "Quran"
        case .location: "Location"
        case .masjid: "Masjid"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .fasting: "fork.knife"
        case .quran: "book"
        case .location: "location"
        case .masjid: "building.columns"
        case .advanced: "slider.horizontal.3"
        }
    }
}
