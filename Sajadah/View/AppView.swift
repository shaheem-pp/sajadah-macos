import SwiftUI
import CoreLocation
import Combine
import AppKit

// MARK: - View

struct AppView: View {
    @StateObject private var location = LocationManager()

    var body: some View {
        Group {
            switch location.state {
            case .loading:
                LoadingView()

            case .home(let coordinate):
                HomeView(coordinate: coordinate)

            case .needPermission:
                LocationPermissionView(
                    onRequest: { location.requestPermission() }
                )

            case .denied:
                LocationDeniedView(
                    onOpenSettings: { openAppSettings() },
                    onRetry: { location.requestPermission() }
                )

            case .error(let message):
                LocationErrorView(
                    message: message,
                    onRetry: { location.refresh() }
                )
            }
        }
        .padding()
        .onAppear {
            location.refresh()
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
        #else
        // Unsupported platform
        #endif
    }
}


#Preview {
    AppView()
}
