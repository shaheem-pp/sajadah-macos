//
//  AdvancedSettingsView.swift
//  Sajadah
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimesStore.self) private var store

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Adjust Adhan times", isOn: $settings.adhanAdjustmentsEnabled)

                if settings.adhanAdjustmentsEnabled {
                    // `store.today` already carries the adjustment, so the preview is the time
                    // the rest of the app is showing — the only way to tell the stepper went
                    // the direction you meant.
                    if let day = store.today {
                        ForEach(DayLog.tracked) { prayer in
                            minuteRow(
                                prayer.displayName,
                                adjustment(for: prayer),
                                range: -30...30,
                                step: 1,
                                valueText: Self.signed(settings.adhanAdjustments.minutes(for: prayer)),
                                preview: TimeFormatting.clock(
                                    day.time(for: prayer),
                                    use24Hour: settings.use24HourClock,
                                    timeZone: day.timeZone
                                )
                            )
                        }
                    } else {
                        Text("Waiting for today’s Adhan times…")
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset to Computed Times") { settings.resetAdhanAdjustments() }
                        .disabled(!settings.adhanAdjustments.isEffective)
                }
            } header: {
                Text("Adhan times")
            } footer: {
                Text("For a community whose calendar runs a few minutes off the computed times. Adjusted times are used everywhere — the menubar, notifications, widgets, and Iqamah computed as minutes after Adhan. Jamaah times read from a masjid website are not changed, and neither is sunrise, which is not an Adhan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func adjustment(for prayer: Prayer) -> Binding<Int> {
        let settings = Bindable(settings)
        return switch prayer {
        case .fajr: settings.adhanAdjustmentFajr
        case .dhuhr: settings.adhanAdjustmentDhuhr
        case .asr: settings.adhanAdjustmentAsr
        case .maghrib: settings.adhanAdjustmentMaghrib
        // Sunrise is never in `DayLog.tracked`; Isha absorbs it to keep the switch total.
        case .isha, .sunrise: settings.adhanAdjustmentIsha
        }
    }

    /// "+3 min", "−2 min", "0 min" — the sign is the whole point of the number.
    private static func signed(_ minutes: Int) -> String {
        switch minutes {
        case ..<0: "−\(-minutes) min"
        case 0: "0 min"
        default: "+\(minutes) min"
        }
    }
}
