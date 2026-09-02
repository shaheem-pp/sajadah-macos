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
            QuranSettingsView()
                .tabItem { Label("Quran", systemImage: "book") }
            LocationSettingsView()
                .tabItem { Label("Location", systemImage: "location") }
            MasjidSettingsView()
                .tabItem { Label("Masjid", systemImage: "building.columns") }
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

// MARK: - Quran

private struct QuranSettingsView: View {
    @Environment(AppSettings.self) private var settings

    private static let sample = "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ"

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Translation", selection: $settings.translationEdition) {
                    ForEach(QuranTranslation.all) { translation in
                        Text(translation.name).tag(translation.id)
                    }
                }
            } footer: {
                Text("Changing translation clears the downloaded surah text and refetches it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Arabic text") {
                Picker("Font", selection: $settings.arabicFontName) {
                    // Filtered so the picker can't offer a font that would silently fall back
                    // to the system face and look like a rendering bug.
                    ForEach(ArabicFontChoice.all.filter { BundledFonts.isAvailable($0.id) }) { choice in
                        Text(choice.isQuranic ? "\(choice.name) — Uthmani" : choice.name)
                            .tag(choice.id)
                    }
                }

                LabeledContent("Arabic size") {
                    Slider(value: $settings.arabicFontSize, in: 16...44, step: 1) {
                        Text("Arabic size")
                    }
                    .frame(width: 180)
                }

                LabeledContent("Translation size") {
                    Slider(value: $settings.translationFontSize, in: 10...22, step: 1) {
                        Text("Translation size")
                    }
                    .frame(width: 180)
                }

                // A live sample matters here: the shipped Arabic faces differ wildly in
                // optical size, so the same point value looks very different between them.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.sample)
                        .font(.arabic(settings.arabicFontName, size: settings.arabicFontSize))
                        .lineSpacing(settings.arabicFontSize * 0.5)
                        .environment(\.layoutDirection, .rightToLeft)
                    Text("Allah — there is no deity except Him, the Ever-Living, the Sustainer.")
                        .font(.system(size: settings.translationFontSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Remind me to read Quran", isOn: $settings.quranReminderEnabled)
                DatePicker("Reminder time", selection: quranTime, displayedComponents: .hourAndMinute)
                    .disabled(!settings.quranReminderEnabled)
            } header: {
                Text("Daily reading")
            } footer: {
                Text("Opens the reader where you left off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Friday") {
                Toggle("Remind me to read Surah Al-Kahf", isOn: $settings.fridayKahfReminder)
                DatePicker("Reminder time", selection: fridayTime, displayedComponents: .hourAndMinute)
                    .disabled(!settings.fridayKahfReminder)
            }

            Section {
                // The OFL asks that the font be distributed with its copyright notice; the
                // licence ships in the app bundle and this credits it in the UI.
                Text("Quran text from alquran.cloud. Amiri Quran typeface © The Amiri Project Authors, used under the SIL Open Font License 1.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var fridayTime: Binding<Date> {
        timeOfDay(Bindable(settings).fridayKahfMinutes, fallbackHour: 9)
    }

    private var quranTime: Binding<Date> {
        timeOfDay(Bindable(settings).quranReminderMinutes, fallbackHour: 20)
    }
}

// MARK: - Time-of-day bindings

/// Times of day are stored as minutes from local midnight — a plain `Int` that survives the
/// user's timezone changing — but `DatePicker` wants a `Date`. Three settings need the same
/// conversion, so it lives here once.
private func timeOfDay(_ minutes: Binding<Int>, fallbackHour: Int) -> Binding<Date> {
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

// MARK: - Masjid

private struct MasjidSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(IqamahStore.self) private var iqamah
    @Environment(PrayerTimesStore.self) private var store
    @State private var urlDraft: String = ""

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Source", selection: $settings.iqamahSourceMode) {
                    Text("Masjid website").tag(AppSettings.IqamahSourceMode.website)
                    Text("Minutes after Athaan").tag(AppSettings.IqamahSourceMode.offset)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch settings.iqamahSourceMode {
            case .website:
                websiteSections(settings: settings)
            case .offset:
                offsetSection(settings: settings)
            }
        }
        .formStyle(.grouped)
        .onAppear { urlDraft = settings.masjidURL ?? "" }
    }

    // MARK: Website

    @ViewBuilder
    private func websiteSections(settings: AppSettings) -> some View {
        Section {
            TextField("https://yourmasjid.org/prayer-times", text: $urlDraft)
                .onSubmit { commit() }
            HStack {
                Button("Save & Check") { commit() }
                if settings.masjidURL != nil {
                    Button("Clear") { urlDraft = ""; commit() }
                }
                Spacer()
                if iqamah.loadState == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } footer: {
            Text("Paste your local masjid’s prayer-times page. Sajadah looks for plain-text prayer labels and times — it works on many small mosque sites, but not all of them (image schedules and pages that render their schedule with JavaScript can’t be read this way — try “Minutes after Athaan” instead for those).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let result = iqamah.lastResult {
            Section {
                ForEach(IqamahLabel.allCases, id: \.self) { label in
                    HStack {
                        Text(label.displayName)
                        Spacer()
                        switch result.match(for: label) {
                        case .found(let value):
                            Text(value)
                                .foregroundStyle(.secondary)
                        case .notFound:
                            Text(label.isCore ? "Not found" : "Not found (optional)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Found on this page")
            } footer: {
                if case .failed(let message) = iqamah.loadState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if iqamah.isStale {
                    Label("Showing the last successful check", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if case .failed(let message) = iqamah.loadState {
            Section {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Saving an unchanged URL still needs to trigger a fetch — `masjidURL`'s own `didSet`
    /// dedupes identical values, but "test again" after the masjid updates its page is exactly
    /// the case where the URL wouldn't have changed.
    private func commit() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = trimmed.isEmpty ? nil : trimmed
        if new == settings.masjidURL {
            iqamah.refresh()
        } else {
            settings.masjidURL = new
        }
    }

    // MARK: Offset

    @ViewBuilder
    private func offsetSection(settings: AppSettings) -> some View {
        Section {
            if let day = store.today {
                let preview = IqamahOffsetCalculator.times(
                    for: day,
                    fajr: settings.iqamahOffsetFajr, dhuhr: settings.iqamahOffsetDhuhr,
                    asr: settings.iqamahOffsetAsr, maghrib: settings.iqamahOffsetMaghrib,
                    isha: settings.iqamahOffsetIsha, use24Hour: settings.use24HourClock
                )
                offsetRow("Fajr", Bindable(settings).iqamahOffsetFajr, preview.fajr)
                offsetRow("Dhuhr", Bindable(settings).iqamahOffsetDhuhr, preview.dhuhr)
                offsetRow("Asr", Bindable(settings).iqamahOffsetAsr, preview.asr)
                offsetRow("Maghrib", Bindable(settings).iqamahOffsetMaghrib, preview.maghrib)
                offsetRow("Isha", Bindable(settings).iqamahOffsetIsha, preview.isha)
            } else {
                Text("Waiting for today’s Adhan times…")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Iqamah times are computed from today’s Adhan times, not fetched from anywhere — nothing to check, and they update automatically as Adhan times do.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func offsetRow(_ label: String, _ minutes: Binding<Int>, _ preview: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: minutes, in: 0...60, step: 5) {
                Text("\(minutes.wrappedValue) min")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            Text(preview)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
        }
    }
}
