//
//  HomeView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI
import CoreLocation



// Replace with your real home screen.
struct HomeView: View {
    let coordinate: CLLocationCoordinate2D

    @State private var placemark: CLPlacemark?
    @State private var isGeocoding = false
    @State private var geocodeError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Location Details")
                    .font(.title)
                    .fontWeight(.semibold)

                // Coordinates
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coordinates")
                        .font(.headline)
                    Text("Latitude: \(String(format: "%.6f", coordinate.latitude))")
                    Text("Longitude: \(String(format: "%.6f", coordinate.longitude))")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Placemark details
                if isGeocoding {
                    ProgressView("Resolving address…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let geocodeError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.headline)
                        Text(geocodeError)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let placemark {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.headline)
                        if let name = placemark.name { Text(name) }
                        if let thoroughfare = placemark.thoroughfare { Text(thoroughfare) }
                        if let subThoroughfare = placemark.subThoroughfare { Text(subThoroughfare) }
                        if let locality = placemark.locality { Text("City: \(locality)") }
                        if let subLocality = placemark.subLocality { Text("Sub‑Locality: \(subLocality)") }
                        if let administrativeArea = placemark.administrativeArea { Text("State/Province: \(administrativeArea)") }
                        if let subAdministrativeArea = placemark.subAdministrativeArea { Text("County: \(subAdministrativeArea)") }
                        if let postalCode = placemark.postalCode { Text("Postal Code: \(postalCode)") }
                        if let country = placemark.country { Text("Country: \(country)") }
                        if let iso = placemark.isoCountryCode { Text("ISO Code: \(iso)") }
                        if let timeZone = placemark.timeZone { Text("Time Zone: \(timeZone.identifier)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Refresh Details") {
                    reverseGeocode()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onAppear { reverseGeocode() }
    }

    private func reverseGeocode() {
        isGeocoding = true
        geocodeError = nil
        placemark = nil

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            isGeocoding = false
            if let error = error {
                geocodeError = error.localizedDescription
                return
            }
            placemark = placemarks?.first
        }
    }
}

