//
//  FastingSettingsView.swift
//  Sajadah
//

import SwiftUI

struct FastingSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimesStore.self) private var store

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Show fasting days", isOn: $settings.fastingEnabled)
                Toggle("Mondays and Thursdays", isOn: $settings.fastingMondayThursday)
                    .disabled(!settings.fastingEnabled)
                Toggle("The white days — 13th, 14th and 15th", isOn: $settings.fastingWhiteDays)
                    .disabled(!settings.fastingEnabled)
                Toggle("Ashura — 9th and 10th of Muḥarram", isOn: $settings.fastingAshura)
                    .disabled(!settings.fastingEnabled)
                Toggle("The day of Arafah — 9 Dhū al-Ḥijjah", isOn: $settings.fastingArafah)
                    .disabled(!settings.fastingEnabled)
            } header: {
                Text("Fasting days")
            } footer: {
                Text("Marked beside the Hijri date in the popover, the window and the Today widget. Ramadan is always marked, with iftar beside the date and one reminder the evening before it begins. Never on either Eid or the days of Tashreeq — 13 Dhū al-Ḥijjah is skipped even though it is a white day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Remind me the evening before", isOn: $settings.fastingRemindersEnabled)

                Picker("Remind me", selection: $settings.fastingReminderMode) {
                    Text("After Maghrib").tag(AppSettings.FastingReminderMode.afterMaghrib)
                    Text("At a time").tag(AppSettings.FastingReminderMode.fixedTime)
                }
                .pickerStyle(.segmented)

                switch settings.fastingReminderMode {
                case .afterMaghrib:
                    Stepper(
                        value: $settings.fastingReminderMinutesAfterMaghrib,
                        in: 0...120,
                        step: 15
                    ) {
                        Text(settings.fastingReminderMinutesAfterMaghrib == 0
                             ? "Remind me at Maghrib"
                             : "Remind me \(settings.fastingReminderMinutesAfterMaghrib) minutes after Maghrib")
                    }
                case .fixedTime:
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminder")
            } footer: {
                Text("Names the day and gives the time of Fajr, so you can plan suhoor. Separate from the prayer-time notifications, like the Iqamah reminder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.fastingEnabled)

            Section {
                // Live: the value moves as the stepper does, which is the only way to tell
                // whether the adjustment went the direction you meant. "Showing" rather than
                // "Today" because after Maghrib it is, correctly, tomorrow's.
                LabeledContent("Showing", value: store.hijriDateText ?? "—")

                Stepper(value: $settings.hijriAdjustmentDays, in: -2...2) {
                    Text(adjustmentLabel)
                }

                Toggle("Date changes at Maghrib", isOn: $settings.hijriChangesAtMaghrib)
            } header: {
                Text("Hijri date")
            } footer: {
                Text("Dates come from the Aladhan calendar — Umm al-Qura, adjusted to Saudi Arabia’s official sighting announcements — and can differ from your community’s by a day. Set +1 if your masjid began the month a day earlier. The date shown in Sajadah and its widgets, and the fasting days above, all follow this adjustment. The Islamic day begins at sunset; turn the Maghrib switch off to match a printed calendar that changes at midnight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var reminderTime: Binding<Date> {
        timeOfDay(Bindable(settings).fastingReminderMinutes, fallbackHour: 20)
    }

    private var adjustmentLabel: String {
        let days = settings.hijriAdjustmentDays
        let unit = abs(days) == 1 ? "day" : "days"
        return switch days {
        case 0: "No adjustment"
        case ..<0: "\(-days) \(unit) behind Aladhan"
        default: "\(days) \(unit) ahead of Aladhan"
        }
    }
}
