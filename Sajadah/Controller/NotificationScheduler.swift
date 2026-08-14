//
//  NotificationScheduler.swift
//  Sajadah
//

import Foundation
import Observation
import UserNotifications

/// Schedules a rolling window of local notifications: prayer times, plus the two-stage
/// "did you pray?" check-ins.
///
/// macOS keeps at most 64 pending requests per app. Rather than rationing each kind
/// separately, every candidate is built, sorted by fire date, and the nearest 60 are kept —
/// so the budget always goes to what happens soonest. The whole batch is rewritten whenever
/// timings, preferences or the prayer log change.
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {

    enum Authorization: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var authorization: Authorization = .unknown

    /// Called when the user answers a check-in. `nil` means "answered, but record nothing".
    @ObservationIgnored var onCheckInResponse: ((Prayer, String, PrayerLogState?) -> Void)?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private static let maxPending = 60

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
    }

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

    // MARK: Scheduling

    func reschedule(
        events: [PrayerEvent],
        checkIns: [PrayerCheckIn],
        settings: AppSettings,
        placeName: String?
    ) async {
        center.removeAllPendingNotificationRequests()
        guard authorization == .granted else { return }

        var candidates: [(fireDate: Date, request: UNNotificationRequest)] = []

        if settings.notificationsEnabled {
            let offset = TimeInterval(settings.reminderOffsetMinutes * 60)
            for event in events where settings.isNotificationEnabled(for: event.prayer) {
                let fireDate = event.date.addingTimeInterval(-offset)
                guard fireDate > .now else { continue }
                candidates.append((fireDate, Self.prayerTimeRequest(
                    for: event,
                    fireDate: fireDate,
                    offsetMinutes: settings.reminderOffsetMinutes,
                    placeName: placeName
                )))
            }
        }

        if settings.checkInsEnabled {
            let lead = TimeInterval(settings.checkInOffsetMinutes * 60)
            for checkIn in checkIns {
                let softDate = checkIn.windowClose.addingTimeInterval(-lead)
                if softDate > .now {
                    candidates.append((softDate, Self.checkInRequest(
                        checkIn,
                        stage: .soft,
                        fireDate: softDate,
                        leadMinutes: settings.checkInOffsetMinutes
                    )))
                }
                if checkIn.windowClose > .now {
                    candidates.append((checkIn.windowClose, Self.checkInRequest(
                        checkIn,
                        stage: .final,
                        fireDate: checkIn.windowClose,
                        leadMinutes: settings.checkInOffsetMinutes
                    )))
                }
            }
        }

        let scheduled = candidates
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxPending)

        for candidate in scheduled {
            try? await center.add(candidate.request)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: Request building

    private static func prayerTimeRequest(
        for event: PrayerEvent,
        fireDate: Date,
        offsetMinutes: Int,
        placeName: String?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.prayer.displayName

        let time = event.date.formatted(date: .omitted, time: .shortened)
        let place = placeName.map { " in \($0)" } ?? ""
        content.body = offsetMinutes > 0
            ? "\(event.prayer.displayName) is in \(offsetMinutes) minute\(offsetMinutes == 1 ? "" : "s") — \(time)\(place)."
            : "It’s time for \(event.prayer.displayName)\(place) — \(time)."
        content.sound = .default

        return request(
            identifier: "time-\(Int(event.date.timeIntervalSince1970))-\(event.prayer.rawValue)",
            content: content,
            fireDate: fireDate
        )
    }

    private enum Stage { case soft, final }

    private static func checkInRequest(
        _ checkIn: PrayerCheckIn,
        stage: Stage,
        fireDate: Date,
        leadMinutes: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Did you pray \(checkIn.prayer.displayName)?"
        content.userInfo = [
            UserInfoKey.prayer: checkIn.prayer.rawValue,
            UserInfoKey.dayKey: checkIn.dayKey,
        ]

        switch stage {
        case .soft:
            content.categoryIdentifier = Category.checkInSoft
            content.body = "\(checkIn.prayer.displayName)’s window closes in \(leadMinutes) minutes."
            content.sound = .default
        case .final:
            content.categoryIdentifier = Category.checkInFinal
            content.body = "Last chance — \(checkIn.prayer.displayName)’s window is closing now."
            // Silent on purpose: the next prayer's own notification fires at this same
            // moment, and two chimes at once is just noise.
            content.sound = nil
        }

        let prefix = stage == .soft ? "checkin-soft" : "checkin-final"
        return request(
            identifier: "\(prefix)-\(checkIn.id)",
            content: content,
            fireDate: fireDate
        )
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
