//
//  MasjidSettingsView.swift
//  Sajadah
//

import SwiftUI

struct MasjidSettingsView: View {
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
        minuteRow(label, minutes, range: 0...60, step: 5, valueText: "\(minutes.wrappedValue) min", preview: preview)
    }
}
