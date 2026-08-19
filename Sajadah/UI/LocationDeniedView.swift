//
//  LocationDeniedView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

struct LocationDeniedView: View {
    let onOpenSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        StatusStateView(
            systemImage: "location.slash",
            title: "Location Access Off",
            message: "Turn on Location Services for Sajadah in System Settings to see your prayer times."
        ) {
            HStack(spacing: 10) {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)

                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
