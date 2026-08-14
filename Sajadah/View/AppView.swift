import AppKit
import SwiftUI

// MARK: - View

/// Root of the main window. Prayer times win whenever we have them — including from the disk
/// cache — so a slow or stalled location fix never blanks a window that has something to show.
struct AppView: View {
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
