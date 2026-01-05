//
//  LocationManager.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import CoreLocation
import Combine


// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case loading
        case home(CLLocationCoordinate2D)
        case needPermission
        case denied
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.needPermission, .needPermission): return true
            case (.denied, .denied): return true
            case (.error(let a), .error(let b)): return a == b
            case (.home(let a), .home(let b)):
                return a.latitude == b.latitude && a.longitude == b.longitude
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .loading

    private let manager = CLLocationManager()
    private var didRequestOnce = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        #if os(macOS)
        let status = manager.authorizationStatus
        #else
        let status = CLLocationManager.authorizationStatus()
        #endif
        updateStateForAuthorization(status)
        if case .home = state {
            // already have location
        } else if isAuthorized(status) {
            requestLocation()
        }
    }

    func requestPermission() {
        #if os(macOS)
        let status = manager.authorizationStatus
        #else
        let status = CLLocationManager.authorizationStatus()
        #endif

        // If not determined, request permission.
        if status == .notDetermined {
            didRequestOnce = true
            manager.requestWhenInUseAuthorization()
            state = .loading
            return
        }

        // If already authorized, request a location update.
        if isAuthorized(status) {
            requestLocation()
            return
        }

        // Otherwise denied/restricted.
        state = .denied
    }

    func requestLocation() {
        state = .loading
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if os(macOS)
        let status = manager.authorizationStatus
        #else
        let status = CLLocationManager.authorizationStatus()
        #endif
        updateStateForAuthorization(status)

        if isAuthorized(status) {
            requestLocation()
        } else if status == .denied || status == .restricted {
            state = .denied
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let best = locations.last else {
            state = .error("No location received.")
            return
        }
        state = .home(best.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .error(error.localizedDescription)
    }

    // MARK: - Helpers

    private func updateStateForAuthorization(_ status: CLAuthorizationStatus) {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            // We'll request location and move to .home when it arrives.
            if case .home = state { return }
            state = .loading

        case .notDetermined:
            // If we already asked and came back notDetermined (rare), keep prompting UI.
            state = .needPermission

        case .denied, .restricted:
            state = .denied

        @unknown default:
            state = .error("Unknown authorization status.")
        }
        #elseif os(macOS)
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            // We'll request location and move to .home when it arrives.
            if case .home = state { return }
            state = .loading

        case .notDetermined:
            // If we already asked and came back notDetermined (rare), keep prompting UI.
            state = .needPermission

        case .denied, .restricted:
            state = .denied

        @unknown default:
            state = .error("Unknown authorization status.")
        }
        #else
        switch status {
        case .authorized, .authorizedAlways:
            if case .home = state { return }
            state = .loading
        case .notDetermined:
            state = .needPermission
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .error("Unknown authorization status.")
        }
        #endif
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        return status == .authorizedAlways || status == .authorizedWhenInUse
        #elseif os(macOS)
        return status == .authorized
        #else
        return false
        #endif
    }
}
