//
//  PrayerDetailView.swift
//  Sajadah
//

import AppKit
import SwiftUI

/// The prayer-times pane of the main window.
///
/// The location permission flow lives here rather than wrapping the whole window, so a denied
/// or failed location never blocks the Quran — reading has nothing to do with where you are.
struct PrayerDetailView: View {
    @Environment(LocationManager.self) private var location
    @Environment(PrayerTimesStore.self) private var store

    var body: some View {
        Group {
            if store.today != nil {
                HomeView()
            } else {
                fallback
                    .padding()
            }
        }
        .navigationTitle("Prayer Times")
        .onAppear { location.refresh() }
    }

    @ViewBuilder
    private var fallback: some View {
        switch location.state {
        case .needPermission:
            LocationPermissionView(onRequest: { location.requestPermission() })

        case .denied:
            LocationDeniedView(
                onOpenSettings: { MenuBarContentView.openLocationSystemSettings() },
                onRetry: { location.requestPermission() }
            )

        case .error(let message):
            LocationErrorView(message: message, onRetry: { location.refresh() })

        case .loading, .home:
            switch store.loadState {
            case .failed(let message):
                LocationErrorView(message: message, onRetry: { store.refresh() })
            default:
                LoadingView()
            }
        }
    }
}
