//
//  AppCoordinator.swift
//  Sajadah
//

import Foundation
import Observation

/// Owns the app's long-lived objects and wires them together.
///
/// This exists because the connections between them have to hold whether or not any view is
/// on screen — the menubar keeps counting down with the popover closed and no window open.
@MainActor
@Observable
final class AppCoordinator {
    let location = LocationManager()
    let settings = AppSettings()
    let store = PrayerTimesStore()
    let log = PrayerLogStore()
    let scheduler = NotificationScheduler()

    @ObservationIgnored private var ticker: Ticker?

    init() {
        store.configure(settings: settings)

        location.onCoordinate = { [store] coordinate in
            store.updateCoordinate(coordinate)
        }
        settings.onCalculationChanged = { [store] in
            store.invalidateAndRefresh()
        }
        settings.onNotificationPreferencesChanged = { [weak self] in
            self?.rescheduleNotifications()
        }
        store.onEventsChanged = { [weak self] in
            self?.rescheduleNotifications()
        }
        // Logging a prayer retires its outstanding questions: the reschedule below rebuilds
        // the batch from scratch and simply omits anything already answered.
        log.onChange = { [weak self] in
            self?.rescheduleNotifications()
        }
        scheduler.onCheckInResponse = { [log] prayer, dayKey, state in
            log.set(state, for: prayer, on: dayKey)
        }

        ticker = Ticker { [store] date in store.tick(date) }
        ticker?.start()

        Task { [weak self] in await self?.start() }
    }

    private func start() async {
        // Ask outright rather than waiting for a button. The window is suppressed at launch
        // and the popover starts closed, so nothing else would ever trigger the prompt —
        // the menubar would just sit there saying "Sajadah".
        location.requestPermission()
        // The disk cache may already hold a coordinate and timings, so show something
        // immediately rather than waiting on CoreLocation.
        store.refreshPlaceNameIfNeeded()
        store.refresh()

        await scheduler.requestAuthorizationIfNeeded()
        rescheduleNotifications()
    }

    private func rescheduleNotifications() {
        Task { [scheduler, store, settings, log] in
            // Questions already answered are never asked again.
            let checkIns = store
                .upcomingCheckIns(limitDays: 3, ishaCutoffMinutes: settings.ishaCutoffMinutes)
                .filter { log.state(for: $0.prayer, on: $0.dayKey) == nil }

            await scheduler.reschedule(
                events: store.upcomingEvents(limitDays: 7),
                checkIns: checkIns,
                settings: settings,
                placeName: store.placeName
            )
        }
    }
}
