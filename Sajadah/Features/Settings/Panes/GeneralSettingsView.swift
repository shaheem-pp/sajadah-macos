//
//  GeneralSettingsView.swift
//  Sajadah
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimesStore.self) private var store
    @Environment(UpdateStore.self) private var update
    @State private var didCopyCommand = false

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
                VStack(alignment: .leading, spacing: 4) {
                    // Automatic is only reassuring once it says what it picked.
                    if settings.calculationMethod == CalculationMethod.automaticID,
                       let resolved = store.resolvedMethod {
                        Text("Using \(resolved.name), chosen for your location.")
                    }
                    Text("Changing either of these refetches prayer times from the Aladhan API.")
                    // The one place a by-hand offset could be mistaken for the method being
                    // wrong, so the method's own pane says where the offset lives.
                    if settings.adhanAdjustments.isEffective {
                        Text("Adhan times are also being adjusted by the minute, under Advanced.")
                    }
                }
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

            updatesSection(settings: settings)
        }
        .formStyle(.grouped)
    }

    // MARK: Updates

    @ViewBuilder
    private func updatesSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings

        Section {
            LabeledContent("Version", value: update.currentVersion.description)

            Toggle("Check for updates automatically", isOn: $settings.updateChecksEnabled)

            LabeledContent {
                HStack(spacing: 8) {
                    if update.isChecking {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check Now") { update.checkNow() }
                        .disabled(update.isChecking)
                }
            } label: {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(update.lastError == nil ? .secondary : Color.red)
            }

            if let release = update.latest, let version = release.version,
               version > update.currentVersion {
                // The app is ad-hoc signed and cannot replace itself: `cp -R` onto a live
                // bundle merges directories rather than replacing them, and a bundle holding
                // files its signature doesn't cover won't open at all. So the useful thing to
                // offer is the command that does it properly.
                LabeledContent("Version \(version)") {
                    HStack(spacing: 8) {
                        Button(didCopyCommand ? "Copied" : "Copy Update Command") {
                            update.copyUpdateCommand()
                            didCopyCommand = true
                        }
                        .disabled(didCopyCommand)
                        Button("Release Notes") { update.openReleasePage() }
                    }
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Sajadah asks GitHub once a day whether a newer release exists. No account, and nothing about you is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: update.latest) { didCopyCommand = false }
    }

    private var status: String {
        if let error = update.lastError { return error }
        if update.isChecking { return "Checking…" }
        guard let checked = update.lastCheckedAt else { return "Not checked yet" }
        if let release = update.latest, let version = release.version,
           version > update.currentVersion {
            return "An update is available"
        }
        return "Up to date · checked \(Self.checkedFormatter.localizedString(for: checked, relativeTo: .now))"
    }

    private static let checkedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
