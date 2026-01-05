//
//  LocationErrorView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//


import SwiftUI
import CoreLocation
import Combine
import AppKit

struct LocationErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Couldn’t Get Location")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
