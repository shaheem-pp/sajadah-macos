//
//  AppSettings.swift
//  Sajadah
//

import Foundation
import Observation
import ServiceManagement

/// User preferences, backed by `UserDefaults`. This is a plain object rather than a pile of
/// `@AppStorage` properties because the store and the notification scheduler need to read it
/// too, not just views.
@Observable
final class AppSettings {

    // MARK: Calculation

    var calculationMethod: Int {
        didSet {
            guard calculationMethod != oldValue else { return }
            defaults.set(calculationMethod, forKey: Key.calculationMethod)
            onCalculationChanged?()
        }
    }

    var asrSchool: AsrSchool {
        didSet {
            guard asrSchool != oldValue else { return }
            defaults.set(asrSchool.rawValue, forKey: Key.asrSchool)
            onCalculationChanged?()
        }
    }

    // MARK: Notifications

    var notificationsEnabled: Bool {
        didSet {
            guard notificationsEnabled != oldValue else { return }
            defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
            onNotificationPreferencesChanged?()
        }
    }

    var enabledPrayers: Set<Prayer> {
        didSet {
            guard enabledPrayers != oldValue else { return }
            defaults.set(enabledPrayers.map(\.rawValue).sorted(), forKey: Key.enabledPrayers)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes *before* the prayer to fire the notification. `0` means at the prayer itself.
    var reminderOffsetMinutes: Int {
        didSet {
            guard reminderOffsetMinutes != oldValue else { return }
            defaults.set(reminderOffsetMinutes, forKey: Key.reminderOffsetMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    // MARK: Iqamah reminders

    /// Whether to be reminded shortly before the masjid's congregation time. Does nothing
    /// until a masjid is configured under Settings → Masjid.
    var iqamahRemindersEnabled: Bool {
        didSet {
            guard iqamahRemindersEnabled != oldValue else { return }
            defaults.set(iqamahRemindersEnabled, forKey: Key.iqamahRemindersEnabled)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes *before* Iqamah to fire that reminder — long enough to still get there.
    var iqamahReminderOffsetMinutes: Int {
        didSet {
            guard iqamahReminderOffsetMinutes != oldValue else { return }
            defaults.set(iqamahReminderOffsetMinutes, forKey: Key.iqamahReminderOffsetMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    // MARK: Check-ins

    /// Whether to ask "did you pray X?" after each Adhan, and again as the window closes.
    var checkInsEnabled: Bool {
        didSet {
            guard checkInsEnabled != oldValue else { return }
            defaults.set(checkInsEnabled, forKey: Key.checkInsEnabled)
            onNotificationPreferencesChanged?()
        }
    }

    /// How long after the Adhan the first ask arrives. Asking here rather than hours later,
    /// near the window close, means the question lands while the answer is still obvious.
    var checkInAfterAdhanMinutes: Int {
        didSet {
            guard checkInAfterAdhanMinutes != oldValue else { return }
            defaults.set(checkInAfterAdhanMinutes, forKey: Key.checkInAfterAdhanMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes from local midnight at which Isha's window is treated as closed. Isha has no
    /// following prayer, so without this there is nothing to hang its check-in on.
    static let defaultIshaCutoffMinutes = 23 * 60

    var ishaCutoffMinutes: Int {
        didSet {
            guard ishaCutoffMinutes != oldValue else { return }
            defaults.set(ishaCutoffMinutes, forKey: Key.ishaCutoffMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    // MARK: Quran

    var translationEdition: String {
        didSet {
            guard translationEdition != oldValue else { return }
            defaults.set(translationEdition, forKey: Key.translationEdition)
            // Cached surah text is tied to an edition, so all of it is now wrong.
            onTranslationChanged?()
        }
    }

    var arabicFontName: String {
        didSet {
            guard arabicFontName != oldValue else { return }
            defaults.set(arabicFontName, forKey: Key.arabicFontName)
        }
    }

    var arabicFontSize: Double {
        didSet {
            guard arabicFontSize != oldValue else { return }
            defaults.set(arabicFontSize, forKey: Key.arabicFontSize)
        }
    }

    var translationFontSize: Double {
        didSet {
            guard translationFontSize != oldValue else { return }
            defaults.set(translationFontSize, forKey: Key.translationFontSize)
        }
    }

    var fridayKahfReminder: Bool {
        didSet {
            guard fridayKahfReminder != oldValue else { return }
            defaults.set(fridayKahfReminder, forKey: Key.fridayKahfReminder)
            onNotificationPreferencesChanged?()
        }
    }

    /// A daily nudge to read, separate from the Friday Al-Kahf one. Off by default — an
    /// unasked-for daily notification is the fastest way to get the app muted entirely.
    var quranReminderEnabled: Bool {
        didSet {
            guard quranReminderEnabled != oldValue else { return }
            defaults.set(quranReminderEnabled, forKey: Key.quranReminderEnabled)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes from local midnight for the daily reading reminder.
    var quranReminderMinutes: Int {
        didSet {
            guard quranReminderMinutes != oldValue else { return }
            defaults.set(quranReminderMinutes, forKey: Key.quranReminderMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes from local midnight for the Friday Al-Kahf reminder.
    var fridayKahfMinutes: Int {
        didSet {
            guard fridayKahfMinutes != oldValue else { return }
            defaults.set(fridayKahfMinutes, forKey: Key.fridayKahfMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    // MARK: Masjid

    /// Where Iqamah times come from: scraped from a masjid's own page, or computed locally as a
    /// fixed number of minutes after each Adhan — the convention at masjids with no posted
    /// schedule of their own, or whose site can't be read this way (e.g. it renders its
    /// schedule with JavaScript, which a plain page fetch never executes).
    enum IqamahSourceMode: String, Sendable {
        case website
        case offset
    }

    var iqamahSourceMode: IqamahSourceMode {
        didSet {
            guard iqamahSourceMode != oldValue else { return }
            defaults.set(iqamahSourceMode.rawValue, forKey: Key.iqamahSourceMode)
            onIqamahSourceChanged?()
        }
    }

    /// `nil` means "not configured" — a meaningfully different state here, since it's what
    /// opts the Iqamah widget out entirely rather than falling back to some default.
    var masjidURL: String? {
        didSet {
            guard masjidURL != oldValue else { return }
            if let masjidURL {
                defaults.set(masjidURL, forKey: Key.masjidURL)
            } else {
                defaults.removeObject(forKey: Key.masjidURL)
            }
            onIqamahSourceChanged?()
        }
    }

    /// Minutes after each Adhan that Iqamah starts, used when `iqamahSourceMode == .offset`.
    /// Defaults follow common practice — Maghrib's window is short, so masjids run it soonest.
    var iqamahOffsetFajr: Int {
        didSet {
            guard iqamahOffsetFajr != oldValue else { return }
            defaults.set(iqamahOffsetFajr, forKey: Key.iqamahOffsetFajr)
            onIqamahSourceChanged?()
        }
    }

    var iqamahOffsetDhuhr: Int {
        didSet {
            guard iqamahOffsetDhuhr != oldValue else { return }
            defaults.set(iqamahOffsetDhuhr, forKey: Key.iqamahOffsetDhuhr)
            onIqamahSourceChanged?()
        }
    }

    var iqamahOffsetAsr: Int {
        didSet {
            guard iqamahOffsetAsr != oldValue else { return }
            defaults.set(iqamahOffsetAsr, forKey: Key.iqamahOffsetAsr)
            onIqamahSourceChanged?()
        }
    }

    var iqamahOffsetMaghrib: Int {
        didSet {
            guard iqamahOffsetMaghrib != oldValue else { return }
            defaults.set(iqamahOffsetMaghrib, forKey: Key.iqamahOffsetMaghrib)
            onIqamahSourceChanged?()
        }
    }

    var iqamahOffsetIsha: Int {
        didSet {
            guard iqamahOffsetIsha != oldValue else { return }
            defaults.set(iqamahOffsetIsha, forKey: Key.iqamahOffsetIsha)
            onIqamahSourceChanged?()
        }
    }

    // MARK: Display

    var use24HourClock: Bool {
        didSet {
            guard use24HourClock != oldValue else { return }
            defaults.set(use24HourClock, forKey: Key.use24HourClock)
        }
    }

    /// Reflects the real `SMAppService` state; setting it registers or unregisters the app.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    private(set) var launchAtLoginError: String?

    // MARK: Change hooks

    /// Called when a change invalidates cached timings (method or Asr school).
    var onCalculationChanged: (() -> Void)?
    /// Called when a change invalidates cached Quran text (translation edition).
    var onTranslationChanged: (() -> Void)?
    /// Called when the set of notifications that should be pending changes.
    var onNotificationPreferencesChanged: (() -> Void)?
    /// Called when anything about where Iqamah times come from changes — the mode, the URL, or
    /// any offset — so the Iqamah store can re-derive them.
    var onIqamahSourceChanged: (() -> Void)?

    // MARK: Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        calculationMethod = defaults.object(forKey: Key.calculationMethod) as? Int
            ?? CalculationMethod.defaultID
        asrSchool = AsrSchool(rawValue: defaults.integer(forKey: Key.asrSchool)) ?? .standard
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        enabledPrayers = (defaults.array(forKey: Key.enabledPrayers) as? [String])
            .map { Set($0.compactMap(Prayer.init(rawValue:))) }
            ?? Set(Prayer.allCases.filter(\.isPrayer))
        reminderOffsetMinutes = defaults.object(forKey: Key.reminderOffsetMinutes) as? Int ?? 0
        iqamahRemindersEnabled = defaults.object(forKey: Key.iqamahRemindersEnabled) as? Bool ?? true
        iqamahReminderOffsetMinutes = defaults.object(forKey: Key.iqamahReminderOffsetMinutes) as? Int ?? 10
        checkInsEnabled = defaults.object(forKey: Key.checkInsEnabled) as? Bool ?? true
        checkInAfterAdhanMinutes = defaults.object(forKey: Key.checkInAfterAdhanMinutes) as? Int ?? 15
        ishaCutoffMinutes = defaults.object(forKey: Key.ishaCutoffMinutes) as? Int ?? Self.defaultIshaCutoffMinutes
        translationEdition = defaults.string(forKey: Key.translationEdition) ?? QuranTranslation.defaultID
        arabicFontName = defaults.string(forKey: Key.arabicFontName) ?? ArabicFontChoice.defaultID
        arabicFontSize = defaults.object(forKey: Key.arabicFontSize) as? Double ?? 26
        translationFontSize = defaults.object(forKey: Key.translationFontSize) as? Double ?? 13
        fridayKahfReminder = defaults.object(forKey: Key.fridayKahfReminder) as? Bool ?? true
        fridayKahfMinutes = defaults.object(forKey: Key.fridayKahfMinutes) as? Int ?? (9 * 60)
        quranReminderEnabled = defaults.object(forKey: Key.quranReminderEnabled) as? Bool ?? false
        quranReminderMinutes = defaults.object(forKey: Key.quranReminderMinutes) as? Int ?? (20 * 60)
        use24HourClock = defaults.object(forKey: Key.use24HourClock) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
        iqamahSourceMode = (defaults.string(forKey: Key.iqamahSourceMode)).flatMap(IqamahSourceMode.init(rawValue:))
            ?? .website
        masjidURL = defaults.string(forKey: Key.masjidURL)
        iqamahOffsetFajr = defaults.object(forKey: Key.iqamahOffsetFajr) as? Int ?? 20
        iqamahOffsetDhuhr = defaults.object(forKey: Key.iqamahOffsetDhuhr) as? Int ?? 15
        iqamahOffsetAsr = defaults.object(forKey: Key.iqamahOffsetAsr) as? Int ?? 15
        iqamahOffsetMaghrib = defaults.object(forKey: Key.iqamahOffsetMaghrib) as? Int ?? 10
        iqamahOffsetIsha = defaults.object(forKey: Key.iqamahOffsetIsha) as? Int ?? 15
    }

    // MARK: Helpers

    func isNotificationEnabled(for prayer: Prayer) -> Bool {
        prayer.isPrayer && enabledPrayers.contains(prayer)
    }

    /// The five offsets as one value, so callers that want the rule rather than five separate
    /// numbers — `IqamahSchedule`, chiefly — don't have to reassemble it themselves.
    var iqamahOffsets: [Prayer: Int] {
        [
            .fajr: iqamahOffsetFajr,
            .dhuhr: iqamahOffsetDhuhr,
            .asr: iqamahOffsetAsr,
            .maghrib: iqamahOffsetMaghrib,
            .isha: iqamahOffsetIsha,
        ]
    }

    func setNotificationEnabled(_ enabled: Bool, for prayer: Prayer) {
        guard prayer.isPrayer else { return }
        if enabled {
            enabledPrayers.insert(prayer)
        } else {
            enabledPrayers.remove(prayer)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Registration fails for unsigned or non-/Applications builds; surface it rather
            // than leaving the toggle silently lying about its state.
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private enum Key {
        static let calculationMethod = "calculationMethod"
        static let asrSchool = "asrSchool"
        static let notificationsEnabled = "notificationsEnabled"
        static let enabledPrayers = "enabledPrayers"
        static let reminderOffsetMinutes = "reminderOffsetMinutes"
        static let iqamahRemindersEnabled = "iqamahRemindersEnabled"
        static let iqamahReminderOffsetMinutes = "iqamahReminderOffsetMinutes"
        static let checkInsEnabled = "checkInsEnabled"
        static let checkInAfterAdhanMinutes = "checkInAfterAdhanMinutes"
        static let ishaCutoffMinutes = "ishaCutoffMinutes"
        static let translationEdition = "translationEdition"
        static let arabicFontName = "arabicFontName"
        static let arabicFontSize = "arabicFontSize"
        static let translationFontSize = "translationFontSize"
        static let fridayKahfReminder = "fridayKahfReminder"
        static let fridayKahfMinutes = "fridayKahfMinutes"
        static let quranReminderEnabled = "quranReminderEnabled"
        static let quranReminderMinutes = "quranReminderMinutes"
        static let use24HourClock = "use24HourClock"
        static let iqamahSourceMode = "iqamahSourceMode"
        static let masjidURL = "masjidURL"
        static let iqamahOffsetFajr = "iqamahOffsetFajr"
        static let iqamahOffsetDhuhr = "iqamahOffsetDhuhr"
        static let iqamahOffsetAsr = "iqamahOffsetAsr"
        static let iqamahOffsetMaghrib = "iqamahOffsetMaghrib"
        static let iqamahOffsetIsha = "iqamahOffsetIsha"
    }
}
