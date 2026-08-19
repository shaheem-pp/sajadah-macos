//
//  AppCoordinator.swift
//  Sajadah
//

import Foundation
import Observation
import WidgetKit

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
    let quran = QuranStore()
    let reading = ReadingProgressStore()
    let navigation = AppNavigation()
    let scheduler = NotificationScheduler()

    @ObservationIgnored private var ticker: Ticker?

    init() {
        // Before anything reads or writes: data written by pre-widget builds lives in
        // Application Support, and would otherwise look like a lost prayer log and streak.
        AppFiles.migrateFromApplicationSupportIfNeeded()

        // Before any view renders, or the reader's first frame falls back to a UI font.
        BundledFonts.registerAll()

        store.configure(settings: settings)
        quran.configure(settings: settings)

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
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Logging a prayer retires its outstanding questions: the reschedule below rebuilds
        // the batch from scratch and simply omits anything already answered.
        log.onChange = { [weak self] in
            self?.rescheduleNotifications()
            // Widgets read the cache rather than polling, so they need telling it moved.
            WidgetCenter.shared.reloadAllTimelines()
        }
        scheduler.onCheckInResponse = { [log] prayer, dayKey, state in
            log.set(state, for: prayer, on: dayKey)
        }
        scheduler.onOpenSurah = { [navigation] surah in
            navigation.openSurah(surah)
        }
        settings.onTranslationChanged = { [quran] in
            quran.invalidateTexts()
        }

        ticker = Ticker { [store, quran] date in
            store.tick(date)
            // Follows the same day boundary the prayer times use, so the verse turns over
            // with everything else rather than at the Mac's midnight.
            quran.refreshDailyAyah(dayKey: store.todayKey)
        }
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

        quran.loadSurahList()
        quran.refreshDailyAyah(dayKey: store.todayKey)

        await scheduler.requestAuthorizationIfNeeded()
        rescheduleNotifications()
        await scheduler.updateFridayKahfReminder(settings: settings)
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
            // Repeating, so it lives outside the rebuild above and must be reapplied here.
            await scheduler.updateFridayKahfReminder(settings: settings)
        }
    }
}
