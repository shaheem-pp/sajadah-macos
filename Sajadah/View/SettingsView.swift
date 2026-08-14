//
//  SettingsView.swift
//  Sajadah
//

import AppKit
import CoreLocation
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            LocationSettingsView()
                .tabItem { Label("Location", systemImage: "location") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Calculation method", selection: $settings.calculationMethod) {
                    ForEach(CalculationMethod.all) { method in
                        Text(method.name).tag(method.id)
                    }
                }
                Picker("Asr calculation", selection: $settings.asrSchool) {
                    ForEach(AsrSchool.allCases) { school in
                        Text(school.displayName).tag(school)
                    }
                }
            } footer: {
                Text("Changing either of these refetches prayer times from the Aladhan API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use 24-hour clock", isOn: $settings.use24HourClock)
                Toggle("Launch Sajadah at login", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationScheduler.self) private var scheduler

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Notify me at prayer times", isOn: $settings.notificationsEnabled)

                if scheduler.authorization == .denied {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Notifications are turned off for Sajadah in System Settings.")
                            .font(.caption)
                        Spacer()
                        Button("Open") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("Prayers") {
                ForEach(Prayer.allCases.filter(\.isPrayer)) { prayer in
                    Toggle(prayer.displayName, isOn: Binding(
                        get: { settings.isNotificationEnabled(for: prayer) },
                        set: { settings.setNotificationEnabled($0, for: prayer) }
                    ))
                }
            }
            .disabled(!settings.notificationsEnabled)

            Section {
                Stepper(
                    value: $settings.reminderOffsetMinutes,
                    in: 0...60,
                    step: 5
                ) {
                    Text(settings.reminderOffsetMinutes == 0
                         ? "Notify at the prayer time"
                         : "Notify \(settings.reminderOffsetMinutes) minutes before")
                }
            }
            .disabled(!settings.notificationsEnabled)

            Section {
                Toggle("Ask whether I prayed", isOn: $settings.checkInsEnabled)

                Stepper(
                    value: $settings.checkInOffsetMinutes,
                    in: 5...30,
                    step: 5
                ) {
                    Text("Ask \(settings.checkInOffsetMinutes) minutes before the window closes")
                }
                .disabled(!settings.checkInsEnabled)

                DatePicker(
                    "Isha window closes at",
                    selection: ishaCutoff,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!settings.checkInsEnabled)
            } header: {
                Text("Check-ins")
            } footer: {
                Text("Each prayer is asked about shortly before its window closes — Fajr before sunrise, Asr before Maghrib, and so on. Answering “Not yet” asks again when the window actually closes; saying no to that marks it missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Isha has no following prayer to bound it, so its window close is a wall-clock time.
    private var ishaCutoff: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.ishaCutoffMinutes / 60,
                    minute: settings.ishaCutoffMinutes % 60,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.ishaCutoffMinutes = (parts.hour ?? 23) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

// MARK: - Location

private struct LocationSettingsView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(LocationManager.self) private var location

    var body: some View {
        Form {
            Section("Current location") {
                LabeledContent("Place", value: store.placeName ?? "Unknown")
                if let coordinate = store.coordinate {
                    LabeledContent("Latitude", value: String(format: "%.4f", coordinate.latitude))
                    LabeledContent("Longitude", value: String(format: "%.4f", coordinate.longitude))
                }
                LabeledContent("Time zone", value: store.displayTimeZone.identifier)
            }

            Section {
                HStack {
                    Button("Update Location") { location.requestLocation() }
                    Button("Refetch Prayer Times") { store.refresh(force: true) }
                    Spacer()
                    if store.isStale {
                        Label("Showing cached times", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
