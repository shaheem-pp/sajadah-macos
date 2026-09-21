//
//  QuranSettingsView.swift
//  Sajadah
//

import SwiftUI

struct QuranSettingsView: View {
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
