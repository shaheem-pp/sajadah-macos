//
//  LocationDeniedView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//


import SwiftUI
import CoreLocation
import Combine
import AppKit

struct LocationDeniedView: View {
    let onOpenSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Location Access Off")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Turn on location in Settings to continue.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)

                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
