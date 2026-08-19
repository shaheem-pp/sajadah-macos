//
//  LocationErrorView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

struct LocationErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        StatusStateView(
            systemImage: "exclamationmark.triangle",
            title: "Couldn’t Get Location",
            message: message
        ) {
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
