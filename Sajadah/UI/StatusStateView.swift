//
//  StatusStateView.swift
//  Sajadah
//

import SwiftUI

/// The shared shape of every "nothing to show yet" state — waiting on location, denied,
/// failed. One component so the popover and the window never drift, and so a permission
/// prompt looks like part of the app rather than a system alert dropped into it.
struct StatusStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var isBusy: Bool = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            emblem

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 260)

            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emblem: some View {
        ZStack {
            MihrabArch()
                .fill(Theme.jade.opacity(0.06))
            MihrabArch()
                .stroke(Theme.jade.opacity(0.25), lineWidth: 1)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 12)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.jade)
                    .padding(.top, 12)
            }
        }
        .frame(width: 54, height: 66)
    }
}
