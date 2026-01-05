//
//  LocationPermissionView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//


import SwiftUI
import CoreLocation
import Combine
import AppKit

struct LocationPermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Enable Location")
                .font(.title2)
                .fontWeight(.semibold)

            Text("We use your location to show accurate prayer times and qibla direction.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Allow Location Access", action: onRequest)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
