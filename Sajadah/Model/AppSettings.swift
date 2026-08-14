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

    // MARK: Check-ins

    /// Whether to ask "did you pray X?" as each prayer's window closes.
    var checkInsEnabled: Bool {
        didSet {
            guard checkInsEnabled != oldValue else { return }
            defaults.set(checkInsEnabled, forKey: Key.checkInsEnabled)
            onNotificationPreferencesChanged?()
        }
    }

    /// How long before the window closes the first, soft ask arrives.
    var checkInOffsetMinutes: Int {
        didSet {
            guard checkInOffsetMinutes != oldValue else { return }
            defaults.set(checkInOffsetMinutes, forKey: Key.checkInOffsetMinutes)
            onNotificationPreferencesChanged?()
        }
    }

    /// Minutes from local midnight at which Isha's window is treated as closed. Isha has no
    /// following prayer, so without this there is nothing to hang its check-in on.
    var ishaCutoffMinutes: Int {
        didSet {
            guard ishaCutoffMinutes != oldValue else { return }
            defaults.set(ishaCutoffMinutes, forKey: Key.ishaCutoffMinutes)
            onNotificationPreferencesChanged?()
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
    /// Called when the set of notifications that should be pending changes.
    var onNotificationPreferencesChanged: (() -> Void)?

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
        checkInsEnabled = defaults.object(forKey: Key.checkInsEnabled) as? Bool ?? true
        checkInOffsetMinutes = defaults.object(forKey: Key.checkInOffsetMinutes) as? Int ?? 10
        ishaCutoffMinutes = defaults.object(forKey: Key.ishaCutoffMinutes) as? Int ?? (23 * 60)
        use24HourClock = defaults.object(forKey: Key.use24HourClock) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Helpers

    func isNotificationEnabled(for prayer: Prayer) -> Bool {
        prayer.isPrayer && enabledPrayers.contains(prayer)
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
        static let checkInsEnabled = "checkInsEnabled"
        static let checkInOffsetMinutes = "checkInOffsetMinutes"
        static let ishaCutoffMinutes = "ishaCutoffMinutes"
        static let use24HourClock = "use24HourClock"
    }
}
