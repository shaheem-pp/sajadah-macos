//
//  SettingsControls.swift
//  Sajadah
//
//  Form pieces more than one pane needs. A row only one pane uses belongs in that pane's file.
//

import SwiftUI

/// Times of day are stored as minutes from local midnight — a plain `Int` that survives the
/// user's timezone changing — but `DatePicker` wants a `Date`. Several settings need the same
/// conversion, so it lives here once.
func timeOfDay(_ minutes: Binding<Int>, fallbackHour: Int) -> Binding<Date> {
    Binding(
        get: {
            Calendar.current.date(
                bySettingHour: minutes.wrappedValue / 60,
                minute: minutes.wrappedValue % 60,
                second: 0,
                of: .now
            ) ?? .now
        },
        set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            minutes.wrappedValue = (parts.hour ?? fallbackHour) * 60 + (parts.minute ?? 0)
        }
    )
}

/// A labelled stepper over a number of minutes with a live clock time beside it — the shape
/// both "Iqamah is N minutes after Adhan" and "this Adhan runs N minutes off" take, so the
/// Masjid and Advanced panes share one row rather than two that drift apart.
func minuteRow(
    _ label: String,
    _ minutes: Binding<Int>,
    range: ClosedRange<Int>,
    step: Int,
    valueText: String,
    preview: String
) -> some View {
    HStack {
        Text(label)
        Spacer()
        Stepper(value: minutes, in: range, step: step) {
            Text(valueText)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        Text(preview)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 76, alignment: .trailing)
    }
}
