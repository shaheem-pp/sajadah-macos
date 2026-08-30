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
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.fridayKahfMinutes / 60,
                    minute: settings.fridayKahfMinutes % 60,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.fridayKahfMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
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
