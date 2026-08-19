//
//  LoadingView.swift
//  Sajadah
//
//  Created by Shaheem on 2026-01-04.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        StatusStateView(
            systemImage: "location",
            title: "Finding your location",
            message: "Prayer times are calculated for where you are right now.",
            isBusy: true
        ) {
            EmptyView()
        }
    }
}
