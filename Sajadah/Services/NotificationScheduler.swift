//
//  NotificationScheduler.swift
//  Sajadah
//

import Foundation
import Observation
import UserNotifications

/// Schedules a rolling window of local notifications: the Adhan, the masjid's Iqamah, and the
/// two "did you pray?" check-ins.
///
/// macOS keeps at most 64 pending requests per app. Rather than rationing each kind separately,
/// every candidate is built, sorted by fire date, and the nearest 60 are kept — so the budget
/// always goes to what happens soonest. The batch is rebuilt whenever timings, preferences or
/// the prayer log change.
///
/// Two things about that rebuild are load-bearing, and both were bugs before:
///
///  - **It is serialised.** Rebuilds are triggered from half a dozen places, and two running at
///    once used to interleave at their `await` points — one would snapshot the pending list,
///    the other would add its requests, and the first would then delete them as stale. Every
///    rebuild now queues behind the last.
///  - **It diffs rather than wipes.** Identifiers are deterministic and `add` replaces a
///    pending request with the same identifier, so only identifiers that are no longer wanted
///    are removed. Removing everything and immediately re-adding it is a race with nothing to
///    gain.
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {

    enum Authorization: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var authorization: Authorization = .unknown

    // MARK: Diagnostics
    //
    // Surfaced in Settings → Notifications. Scheduling failures used to be swallowed by
    // `try?`, which left "notifications don't work sometimes" with nothing to look at.

    private(set) var pendingCount = 0
    private(set) var nextFireDate: Date?
    private(set) var lastError: String?

    /// Called when the user answers a check-in. `nil` means "answered, but record nothing".
    @ObservationIgnored var onCheckInResponse: ((Prayer, String, PrayerLogState?) -> Void)?

    /// Called when a notification asks the app to open a surah.
    @ObservationIgnored var onOpenSurah: ((Int) -> Void)?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private static let maxPending = 60

    /// The tail of the rebuild queue. Each rebuild awaits this before starting, so no two ever
    /// overlap.
    @ObservationIgnored private var work: Task<Void, Never>?

    private enum Category {
        static let checkInSoft = "prayer-checkin-soft"
        static let checkInFinal = "prayer-checkin-final"
    }

    private enum Action {
        static let yes = "log-prayed"
        static let no = "log-not-prayed"
    }

    private enum UserInfoKey {
        static let prayer = "prayer"
        static let dayKey = "dayKey"
        static let surah = "surah"
    }

    /// Al-Kahf. Traditionally read on Fridays.
    private static let kahfSurah = 18
    private static let kahfIdentifier = "friday-al-kahf"
    private static let quranDailyIdentifier = "quran-daily"

    /// Repeating requests, which are owned by `updateRepeatingReminders(settings:surah:)`
    /// rather than by the rebuild. They are excluded from the stale sweep — a repeating
    /// trigger destroyed and recreated every time anything changed would drift.
    private static let repeatingIdentifiers: Set<String> = [kahfIdentifier, quranDailyIdentifier]

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    private func registerCategories() {
        // Two categories with the same buttons but different consequences: "No" on the soft
        // ask means "not yet", "No" on the final ask means the window closed unprayed.
        let soft = UNNotificationCategory(
            identifier: Category.checkInSoft,
            actions: [
                UNNotificationAction(identifier: Action.yes, title: "Yes", options: []),
                UNNotificationAction(identifier: Action.no, title: "Not yet", options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
        let final = UNNotificationCategory(
            identifier: Category.checkInFinal,
            actions: [
                UNNotificationAction(identifier: Action.yes, title: "Yes", options: []),
                UNNotificationAction(identifier: Action.no, title: "No", options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([soft, final])
    }

    // MARK: Authorization

    func requestAuthorizationIfNeeded() async {
        let current = await center.notificationSettings().authorizationStatus
        switch current {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorization = granted ? .granted : .denied
        case .denied:
            authorization = .denied
        default:
            authorization = .granted
        }
    }

    /// Re-reads the real authorization state.
    ///
    /// Called at the top of every rebuild, and again whenever the app becomes active. Caching
    /// the answer from launch meant a user who turned notifications back on in System Settings
    /// stayed silently `.denied` until the next relaunch.
    func refreshAuthorization() async {
        let current = await center.notificationSettings().authorizationStatus
        authorization = switch current {
        case .notDetermined, .denied: .denied
        default: .granted
        }
    }

    // MARK: Scheduling

    /// Rebuilds the pending batch. Safe to call from anywhere, as often as you like: calls
    /// queue behind each other rather than racing.
    ///
    /// - Parameters:
    ///   - prayers: Every prayer still worth scheduling something for, nearest first.
    ///   - checkIns: Window closes, which the final "last chance" ask hangs off.
    ///   - fastingDays: Sunnah fasting days ahead, each with the evening before it.
    ///   - answered: Ids (`PrayerCheckIn.id` / `UpcomingPrayer.id`) already logged — asking
    ///     again about a prayer the user has answered is the fastest way to get muted.
    ///   - surah: The surah a Quran reminder should open.
    func reschedule(
        prayers: [UpcomingPrayer],
        checkIns: [PrayerCheckIn],
        fastingDays: [FastingDay],
        answered: Set<String>,
        settings: AppSettings,
        placeName: String?,
        surah: Int
    ) async {
        let previous = work
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await rebuild(
                prayers: prayers,
                checkIns: checkIns,
                fastingDays: fastingDays,
                answered: answered,
                settings: settings,
                placeName: placeName,
                surah: surah
            )
        }
        work = task
        await task.value
    }

    private func rebuild(
        prayers: [UpcomingPrayer],
        checkIns: [PrayerCheckIn],
        fastingDays: [FastingDay],
        answered: Set<String>,
        settings: AppSettings,
        placeName: String?,
        surah: Int
    ) async {
        await refreshAuthorization()

        // Checked before anything is removed. Bailing out *after* a wipe was how a transient
        // "not granted yet" at launch could leave the user with no notifications at all.
        guard authorization == .granted else {
            pendingCount = 0
            nextFireDate = nil
            return
        }

        lastError = nil

        // One snapshot, shared by the repeating reminders and the stale sweep below.
        let pending = await center.pendingNotificationRequests()
        await updateRepeatingReminders(settings: settings, surah: surah, pending: pending)

        var candidates: [(fireDate: Date, request: UNNotificationRequest)] = []
        let now = Date.now

        if settings.notificationsEnabled {
            let offset = TimeInterval(settings.reminderOffsetMinutes * 60)
            for prayer in prayers where settings.isNotificationEnabled(for: prayer.prayer) {
                let fireDate = prayer.adhan.addingTimeInterval(-offset)
                guard fireDate > now else { continue }
                candidates.append((fireDate, Self.adhanRequest(
                    prayer,
                    fireDate: fireDate,
                    offsetMinutes: settings.reminderOffsetMinutes,
                    placeName: placeName
                )))
            }
        }

        // Deliberately not gated on `notificationsEnabled`: that switch is about the Adhan.
        // Wanting a nudge before jamaah without a ping at every Adhan is a coherent choice.
        if settings.iqamahRemindersEnabled {
            let lead = TimeInterval(settings.iqamahReminderOffsetMinutes * 60)
            for prayer in prayers where settings.isNotificationEnabled(for: prayer.prayer) {
                guard let iqamah = prayer.iqamah else { continue }
                let fireDate = iqamah.addingTimeInterval(-lead)
                // A reminder at or before the Adhan is just the Adhan notification again —
                // which is what a 10-minute lead on a 10-minute Iqamah offset would produce.
                guard fireDate > now, fireDate > prayer.adhan else { continue }
                candidates.append((fireDate, Self.iqamahRequest(
                    prayer,
                    iqamah: iqamah,
                    fireDate: fireDate,
                    leadMinutes: settings.iqamahReminderOffsetMinutes
                )))
            }
        }

        // Also independent of `notificationsEnabled`, for the same reason as Iqamah. One-shots
        // rather than repeating weekday triggers: the white days move with the Hijri calendar,
        // and a Monday in Ramadan or on Eid must not fire at all.
        if settings.fastingEnabled && settings.fastingRemindersEnabled {
            for day in fastingDays {
                let fireDate: Date? = switch settings.fastingReminderMode {
                case .afterMaghrib:
                    day.eve.maghrib.addingTimeInterval(TimeInterval(settings.fastingReminderMinutesAfterMaghrib * 60))
                case .fixedTime:
                    day.eve.localTime(minutesFromMidnight: settings.fastingReminderMinutes)
                }
                guard let fireDate, fireDate > now else { continue }
                candidates.append((fireDate, Self.fastingRequest(day, fireDate: fireDate)))
            }
        }

        if settings.checkInsEnabled {
            let delay = TimeInterval(settings.checkInAfterAdhanMinutes * 60)
            for prayer in prayers where !answered.contains(prayer.id) {
                let fireDate = prayer.adhan.addingTimeInterval(delay)
                guard fireDate > now else { continue }
                candidates.append((fireDate, Self.checkInRequest(
                    prayer: prayer.prayer,
                    dayKey: prayer.dayKey,
                    stage: .soft,
                    fireDate: fireDate,
                    minutes: settings.checkInAfterAdhanMinutes
                )))
            }

            for checkIn in checkIns where !answered.contains(checkIn.id) {
                guard checkIn.windowClose > now else { continue }
                candidates.append((checkIn.windowClose, Self.checkInRequest(
                    prayer: checkIn.prayer,
                    dayKey: checkIn.dayKey,
                    stage: .final,
                    fireDate: checkIn.windowClose,
                    minutes: settings.checkInAfterAdhanMinutes
                )))
            }
        }

        let scheduled = candidates
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxPending)
        let wanted = Set(scheduled.map(\.request.identifier))

        // Only what is no longer wanted. `add` replaces a same-identifier request on its own,
        // so removing something we are about to re-add would be a race for no reason.
        let stale = pending
            .map(\.identifier)
            .filter { !wanted.contains($0) && !Self.repeatingIdentifiers.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        for candidate in scheduled {
            do {
                try await center.add(candidate.request)
            } catch {
                lastError = error.localizedDescription
            }
        }

        await refreshDiagnostics()
    }

    /// Reads back what the system actually holds, rather than what we believe we sent it.
    private func refreshDiagnostics() async {
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.count
        nextFireDate = pending
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
    }

    /// The Friday Al-Kahf and daily Quran reminders are single repeating requests, so they sit
    /// outside the rebuild's diff — that sweep would otherwise destroy and recreate a repeating
    /// trigger every time anything else changed.
    private func updateRepeatingReminders(
        settings: AppSettings,
        surah: Int,
        pending: [UNNotificationRequest]
    ) async {
        await update(
            identifier: Self.kahfIdentifier,
            enabled: settings.fridayKahfReminder,
            title: "Surah Al-Kahf",
            body: "It’s Friday — a good time to read Surah Al-Kahf.",
            surah: Self.kahfSurah,
            // weekday 1 is Sunday in the Gregorian calendar, so Friday is 6.
            components: DateComponents(
                hour: settings.fridayKahfMinutes / 60,
                minute: settings.fridayKahfMinutes % 60,
                weekday: 6
            ),
            pending: pending
        )

        await update(
            identifier: Self.quranDailyIdentifier,
            enabled: settings.quranReminderEnabled,
            title: "Quran",
            body: "A few minutes with the Quran.",
            surah: surah,
            components: DateComponents(
                hour: settings.quranReminderMinutes / 60,
                minute: settings.quranReminderMinutes % 60
            ),
            pending: pending
        )
    }

    private func update(
        identifier: String,
        enabled: Bool,
        title: String,
        body: String,
        surah: Int,
        components: DateComponents,
        pending: [UNNotificationRequest]
    ) async {
        let existing = pending.first { $0.identifier == identifier }

        guard enabled, authorization == .granted else {
            if existing != nil {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
            return
        }

        // Already pending for the same moment, opening the same surah: leave it alone.
        // Rebuilds are frequent, and re-adding a repeating request in the instant it was due
        // to fire is a good way to lose that day's delivery.
        if let trigger = existing?.trigger as? UNCalendarNotificationTrigger,
           trigger.dateComponents == components,
           existing?.content.userInfo[UserInfoKey.surah] as? Int == surah {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [UserInfoKey.surah: surah]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Request building

    private static func adhanRequest(
        _ prayer: UpcomingPrayer,
        fireDate: Date,
        offsetMinutes: Int,
        placeName: String?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = prayer.prayer.displayName

        let time = prayer.adhan.formatted(date: .omitted, time: .shortened)
        let place = placeName.map { " in \($0)" } ?? ""
        content.body = offsetMinutes > 0
            ? "\(prayer.prayer.displayName) is in \(minutes(offsetMinutes)) — \(time)\(place)."
            : "It’s time for \(prayer.prayer.displayName)\(place) — \(time)."
        content.sound = .default

        return request(
            identifier: "adhan-\(prayer.id)",
            content: content,
            fireDate: fireDate
        )
    }

    private static func iqamahRequest(
        _ prayer: UpcomingPrayer,
        iqamah: Date,
        fireDate: Date,
        leadMinutes: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(prayer.prayer.displayName) Iqamah"
        let time = iqamah.formatted(date: .omitted, time: .shortened)
        content.body = "Jamaah for \(prayer.prayer.displayName) is in \(minutes(leadMinutes)) — \(time)."
        content.sound = .default

        return request(
            identifier: "iqamah-\(prayer.id)",
            content: content,
            fireDate: fireDate
        )
    }

    private static func fastingRequest(_ day: FastingDay, fireDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = day.reasons.contains(.ramadan) ? "Ramadan begins tomorrow" : "Fasting tomorrow"
        let fajr = day.fajr.formatted(date: .omitted, time: .shortened)
        content.body = "\(fastingSentence(for: day)) Fajr is at \(fajr)."
        content.sound = .default

        return request(
            identifier: "fast-\(day.dayKey)",
            content: content,
            fireDate: fireDate
        )
    }

    /// Reads correctly whether the displayed date has already turned over at Maghrib or
    /// won't until midnight, because it names the civil day and the fast only.
    private static func fastingSentence(for day: FastingDay) -> String {
        let weekday = day.reasons.first(where: \.isWeekday)?.displayName
        let dated = datedPhrase(for: day)

        switch (weekday, dated) {
        case (let weekday?, let dated?):
            return "Tomorrow is \(weekday) and \(dated)."
        case (let weekday?, nil):
            return "Tomorrow is \(weekday), a sunnah fasting day."
        case (nil, let dated?):
            // "First of the three" only when it is: in Dhū al-Ḥijjah the 13th is skipped, and
            // calling the 14th "second" would then be wrong.
            if day.reasons == [.whiteDay], day.hijri.day == 13 {
                return "The white days begin tomorrow — \(day.hijri.dayAndMonth)."
            }
            return "Tomorrow is \(dated)."
        case (nil, nil):
            return "Tomorrow is a sunnah fasting day."
        }
    }

    /// The part of the sentence that names a Hijri date, for the reasons that come from one.
    /// At most one applies on any day — a white day is never the 9th or 10th of anything.
    private static func datedPhrase(for day: FastingDay) -> String? {
        let date = day.hijri.dayAndMonth
        if day.reasons.contains(.ramadan) { return date }
        if day.reasons.contains(.tasua) { return "\(date), the day before Ashura — fasted alongside the 10th" }
        if day.reasons.contains(.ashura) { return "Ashura, \(date)" }
        if day.reasons.contains(.arafah) { return "the day of Arafah, \(date)" }
        if day.reasons.contains(.whiteDay) { return "\(date), one of the three white days" }
        return nil
    }

    private enum Stage { case soft, final }

    private static func checkInRequest(
        prayer: Prayer,
        dayKey: String,
        stage: Stage,
        fireDate: Date,
        minutes minuteCount: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Did you pray \(prayer.displayName)?"
        content.userInfo = [
            UserInfoKey.prayer: prayer.rawValue,
            UserInfoKey.dayKey: dayKey,
        ]

        let identifier: String
        switch stage {
        case .soft:
            content.categoryIdentifier = Category.checkInSoft
            content.body = "It’s been \(minutes(minuteCount)) since the \(prayer.displayName) Adhan."
            content.sound = .default
            identifier = "checkin-after-\(dayKey)-\(prayer.rawValue)"
        case .final:
            content.categoryIdentifier = Category.checkInFinal
            content.body = "Last chance — \(prayer.displayName)’s window is closing now."
            // Silent on purpose: the next prayer's own notification fires at this same
            // moment, and two chimes at once is just noise.
            content.sound = nil
            identifier = "checkin-final-\(dayKey)-\(prayer.rawValue)"
        }

        return request(identifier: identifier, content: content, fireDate: fireDate)
    }

    private static func minutes(_ count: Int) -> String {
        "\(count) minute\(count == 1 ? "" : "s")"
    }

    private static func request(
        identifier: String,
        content: UNMutableNotificationContent,
        fireDate: Date
    ) -> UNNotificationRequest {
        // Calendar components rather than a time interval: interval triggers drift across
        // sleep, and these can sit pending for days.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Without this, notifications are swallowed whenever Sajadah happens to be frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content

        if let surah = content.userInfo[UserInfoKey.surah] as? Int {
            onOpenSurah?(surah)
            return
        }

        guard let raw = content.userInfo[UserInfoKey.prayer] as? String,
              let prayer = Prayer(rawValue: raw),
              let dayKey = content.userInfo[UserInfoKey.dayKey] as? String else { return }

        switch response.actionIdentifier {
        case Action.yes:
            onCheckInResponse?(prayer, dayKey, .prayed)

        case Action.no:
            // "Not yet" on the soft ask records nothing — there is still time, and the final
            // ask will come when the window actually closes. Only that one marks it missed.
            if content.categoryIdentifier == Category.checkInFinal {
                onCheckInResponse?(prayer, dayKey, .missed)
            }

        default:
            break
        }
    }
}
