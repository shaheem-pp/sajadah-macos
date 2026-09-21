//
//  LocationSettingsView.swift
//  Sajadah
//

import CoreLocation
import SwiftUI

struct LocationSettingsView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(LocationManager.self) private var location

    var body: some View {
        Form {
            Section("Current location") {
                LabeledContent("Place", value: store.placeName ?? "Unknown")
                if let coordinate = store.coordinate {
                    LabeledContent("Latitude", value: String(format: "%.4f", coordinate.latitude))
                    LabeledContent("Longitude", value: String(format: "%.4f", coordinate.longitude))
                }
                LabeledContent("Time zone", value: store.displayTimeZone.identifier)
            }

            Section {
                HStack {
                    Button("Update Location") { location.requestLocation() }
                    Button("Refetch Prayer Times") { store.refresh(force: true) }
                    Spacer()
                    if store.isStale {
                        Label("Showing cached times", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
