//
//  LogButton.swift
//  Sajadah
//

import SwiftUI

/// The tap-to-log circle beside a prayer: hollow until answered, jade tick for prayed, orange
/// cross for missed. Shared by the day's list and the streak grid's editor, so a logged prayer
/// looks the same wherever it is logged from.
struct LogButton: View {
    let state: PrayerLogState?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .prayed:
                    Circle().fill(Theme.jade)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)

                case .missed:
                    Circle().fill(Color.orange.opacity(0.18))
                    Circle().strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)

                case nil:
                    Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.2)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.25)
        .animation(.snappy(duration: 0.18), value: state)
        .help(helpText)
    }

    private var helpText: String {
        switch state {
        case .prayed: "Prayed — click to mark missed"
        case .missed: "Missed — click to clear"
        case nil: "Click to mark as prayed"
        }
    }
}
