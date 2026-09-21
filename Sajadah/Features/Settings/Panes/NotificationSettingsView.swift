//
//  NotificationSettingsView.swift
//  Sajadah
//

import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationScheduler.self) private var scheduler
    @Environment(IqamahStore.self) private var iqamah

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
                Toggle("Remind me before Iqamah", isOn: $settings.iqamahRemindersEnabled)

                Stepper(
                    value: $settings.iqamahReminderOffsetMinutes,
                    in: 0...30,
                    step: 5
                ) {
                    Text(settings.iqamahReminderOffsetMinutes == 0
                         ? "Remind me at Iqamah"
                         : "Remind me \(settings.iqamahReminderOffsetMinutes) minutes before Iqamah")
                }
                .disabled(!settings.iqamahRemindersEnabled)

                if settings.iqamahRemindersEnabled && iqamah.times == nil {
                    Label(
                        "No masjid configured yet — set one up under Masjid.",
                        systemImage: "building.columns"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Iqamah")
            } footer: {
                Text("Uses your masjid’s congregation times and the per-prayer choices above. Separate from the prayer-time notifications, so you can be nudged for jamaah without a ping at every Adhan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ask whether I prayed", isOn: $settings.checkInsEnabled)

                Stepper(
                    value: $settings.checkInAfterAdhanMinutes,
                    in: 5...60,
                    step: 5
                ) {
                    Text("Ask \(settings.checkInAfterAdhanMinutes) minutes after the Adhan")
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
                Text("Each prayer is asked about shortly after its Adhan, while the answer is still obvious. Answering “Not yet” asks once more when the window closes — Fajr at sunrise, Asr at Maghrib, and so on; saying no to that marks it missed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scheduled") {
                scheduleStatus
            }
        }
        .formStyle(.grouped)
    }

    /// What the system is actually holding, not what the settings above imply it should be.
    /// "Notifications didn't fire" is otherwise a report with nothing to look at.
    @ViewBuilder
    private var scheduleStatus: some View {
        LabeledContent("Pending") {
            Text("\(scheduler.pendingCount)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        LabeledContent("Next") {
            Text(scheduler.nextFireDate.map {
                TimeFormatting.clock($0, use24Hour: settings.use24HourClock, timeZone: .current)
            } ?? "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        if let error = scheduler.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    /// Isha has no following prayer to bound it, so its window close is a wall-clock time.
    private var ishaCutoff: Binding<Date> {
        timeOfDay(Bindable(settings).ishaCutoffMinutes, fallbackHour: 23)
    }
}
