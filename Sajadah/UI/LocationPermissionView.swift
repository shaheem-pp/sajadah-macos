//
//  LocationPermissionView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

struct LocationPermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        StatusStateView(
            systemImage: "location",
            title: "Enable Location",
            message: "Sajadah uses your location to calculate accurate prayer times for where you are."
        ) {
            Button("Allow Location Access", action: onRequest)
                .buttonStyle(.borderedProminent)
        }
    }
}
