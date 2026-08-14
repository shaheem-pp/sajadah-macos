//
//  LocationManager.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import AppKit
import CoreLocation
import Observation

// MARK: - Location Manager

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
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

    private(set) var state: State = .loading

    /// Called every time a fresh fix arrives. A direct callback beats observing `state`:
    /// the store must be told about a new coordinate even when no view is on screen.
    @ObservationIgnored var onCoordinate: ((CLLocationCoordinate2D) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        observeWake()
    }

    func refresh() {
        let status = manager.authorizationStatus
        updateStateForAuthorization(status)
        if case .home = state {
            // already have location
        } else if isAuthorized(status) {
            requestLocation()
        }
    }

    func requestPermission() {
        let status = manager.authorizationStatus

        // If not determined, request permission.
        if status == .notDetermined {
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
        if case .home = state {} else { state = .loading }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
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
        onCoordinate?(best.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure should not throw away a coordinate we already have — the
        // menubar can keep counting down from the last known position.
        if case .home = state { return }
        state = .error(error.localizedDescription)
    }

    // MARK: - Helpers

    /// The Mac may have been closed in one city and opened in another.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    private func updateStateForAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            // We'll request location and move to .home when it arrives.
            if case .home = state { return }
            state = .loading

        case .notDetermined:
            state = .needPermission

        case .denied, .restricted:
            state = .denied

        @unknown default:
            state = .error("Unknown authorization status.")
        }
    }

    /// macOS has no `.authorizedWhenInUse` — `requestWhenInUseAuthorization()` resolves to
    /// `.authorizedAlways` (the same raw value as the deprecated `.authorized`).
    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways
    }
}
