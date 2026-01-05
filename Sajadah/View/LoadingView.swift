//
//  LoadingView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//


import SwiftUI
import CoreLocation
import Combine
import AppKit

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Getting your location…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
