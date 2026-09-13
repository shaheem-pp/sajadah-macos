//
//  AppCoordinator.swift
//  Sajadah
//

import AppKit
import Foundation
import Observation
import SwiftUI
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
    let iqamah = IqamahStore()
    let log = PrayerLogStore()
    let quran = QuranStore()
    let reading = ReadingProgressStore()
    let navigation = AppNavigation()
    let scheduler = NotificationScheduler()
    let update = UpdateStore()

    @ObservationIgnored private var ticker: Ticker?

    init() {
        // Before anything reads or writes: data written by pre-widget builds lives in
        // Application Support, and would otherwise look like a lost prayer log and streak.
        AppFiles.migrateFromApplicationSupportIfNeeded()

        // Widgets on an unsigned build read a mirror of the cache rather than the App Group
        // container macOS won't let them touch. Cache writes keep it current, but a Mac that
        // already has today's timings won't do one — so seed it at launch too.
        AppFiles.refreshWidgetMirror()

        // Before any view renders, or the reader's first frame falls back to a UI font.
        BundledFonts.registerAll()

        store.configure(settings: settings)
        iqamah.configure(settings: settings, prayerTimes: store)
        quran.configure(settings: settings)
        update.configure(settings: settings)

        location.onCoordinate = { [store] coordinate in
            store.updateCoordinate(coordinate)
        }
        settings.onCalculationChanged = { [store] in
            store.invalidateAndRefresh()
        }
        settings.onAdhanAdjustmentsChanged = { [store, iqamah, settings] in
            store.adhanAdjustmentsChanged()
            // Iqamah computed as minutes after Adhan has to follow the Adhan; a masjid's own
            // posted times don't, so the scrape is left alone.
            if settings.iqamahSourceMode == .offset { iqamah.refresh() }
        }
        settings.onNotificationPreferencesChanged = { [weak self] in
            self?.rescheduleNotifications()
        }
        store.onEventsChanged = { [weak self] in
            self?.rescheduleNotifications()
            WidgetCenter.shared.reloadAllTimelines()
        }
        settings.onIqamahSourceChanged = { [iqamah] in
            iqamah.refresh()
        }
        settings.onCalendarChanged = { [weak self] in
            guard let self else { return }
            store.syncPreferencesToCache()
            // Fasting reminders hang off the adjusted date, so they may have moved a day.
            rescheduleNotifications()
            WidgetCenter.shared.reloadAllTimelines()
        }
        iqamah.onTimesChanged = { [weak self] in
            // Iqamah reminders are scheduled from these times, so a masjid change has to reach
            // the scheduler and not just the widgets.
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

        ticker = Ticker(countdownTarget: { [store] in store.menuBarTarget }) { [weak self, store, quran, iqamah] date in
            store.tick(date, iqamah: iqamah.times)
            // Follows the same day boundary the prayer times use, so the verse turns over
            // with everything else rather than at the Mac's midnight.
            quran.refreshDailyAyah(dayKey: store.todayKey)
            iqamah.tick(date)
            self?.topUpNotificationsIfStale(at: date)
            // Guarded on a day having passed, so this is two comparisons almost every tick.
            // Launch-only checking would mean a Mac left running for a month never notices a
            // release at all.
            self?.update.checkIfDue()
        }
        ticker?.start()

        // Sajadah is a menubar app: no window open, no Dock icon.
        DockVisibility.start()

        observeActivation()

        Task { [weak self] in await self?.start() }
    }

    /// Re-checks notification permission whenever the app comes forward.
    ///
    /// Someone who turns Sajadah's notifications back on in System Settings never comes back
    /// through the app's own prompt, so without this the scheduler would keep believing it was
    /// denied until the next launch.
    private func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let before = self.scheduler.authorization
                await self.scheduler.refreshAuthorization()
                if self.scheduler.authorization != before { self.rescheduleNotifications() }
            }
        }
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
        iqamah.refresh()

        quran.loadSurahList()
        quran.refreshDailyAyah(dayKey: store.todayKey)
        update.checkIfDue()

        await scheduler.requestAuthorizationIfNeeded()
        rescheduleNotifications()
    }

    // MARK: Notifications

    /// How far ahead notifications are scheduled. Three kinds per prayer plus the closing ask
    /// is around twenty a day against macOS's 64-request budget, so a longer horizon would only
    /// build candidates that get trimmed away unscheduled.
    private static let scheduleHorizonDays = 3

    /// How long the batch may go untouched before the ticker rebuilds it anyway.
    private static let scheduleTopUpInterval: TimeInterval = 30 * 60

    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?
    @ObservationIgnored private var lastRescheduledAt: Date?

    /// Rebuilds the pending notifications, coalescing bursts.
    ///
    /// Dragging a stepper in Settings fires this on every step, and each rebuild is several
    /// round trips to the notification daemon. The short delay collapses that into one pass;
    /// the scheduler serialises whatever still overlaps.
    private func rescheduleNotifications() {
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await performReschedule()
        }
    }

    private func performReschedule() async {
        lastRescheduledAt = .now

        // Questions already answered are never asked again.
        let checkIns = store.upcomingCheckIns(
            limitDays: Self.scheduleHorizonDays,
            ishaCutoffMinutes: settings.ishaCutoffMinutes
        )
        let prayers = store.upcomingPrayers(
            limitDays: Self.scheduleHorizonDays,
            iqamah: iqamahSchedule
        )
        var answered: Set<String> = []
        for prayer in prayers where log.state(for: prayer.prayer, on: prayer.dayKey) != nil {
            answered.insert(prayer.id)
        }
        for checkIn in checkIns where log.state(for: checkIn.prayer, on: checkIn.dayKey) != nil {
            answered.insert(checkIn.id)
        }

        await scheduler.reschedule(
            prayers: prayers,
            checkIns: checkIns,
            fastingDays: store.upcomingFastingDays(limitDays: Self.scheduleHorizonDays),
            answered: answered,
            settings: settings,
            placeName: store.placeName,
            surah: reading.lastRead?.surah ?? 1
        )
    }

    /// The rule Iqamah times follow, rather than today's computed result — the scheduler needs
    /// tomorrow's jamaah too, and in offset mode `IqamahStore.times` only ever describes today.
    private var iqamahSchedule: IqamahSchedule? {
        switch settings.iqamahSourceMode {
        case .offset:
            IqamahSchedule(source: .offsets(settings.iqamahOffsets))
        case .website:
            iqamah.times.map { IqamahSchedule(source: .posted($0)) }
        }
    }

    /// A safety net, called once a second by the ticker and doing nothing almost every time.
    ///
    /// Day rollover, wake and clock changes all rebuild the batch already. This covers the case
    /// none of them do: a Mac left running with nothing changing, where a batch that somehow
    /// went missing would otherwise stay missing.
    private func topUpNotificationsIfStale(at date: Date) {
        guard let last = lastRescheduledAt else { return }
        guard date.timeIntervalSince(last) > Self.scheduleTopUpInterval else { return }
        rescheduleNotifications()
    }
}

// MARK: - Environment

extension View {
    /// Injects every long-lived store into the environment in one call.
    ///
    /// `SajadahApp` has three scenes — menubar, window and Settings — and each needs the full
    /// set. Listing them per scene meant a new store had to be wired in three places, and
    /// missing one failed at runtime in whichever scene was forgotten rather than at compile
    /// time.
    func sajadahEnvironment(_ app: AppCoordinator) -> some View {
        self
            .environment(app.location)
            .environment(app.settings)
            .environment(app.store)
            .environment(app.iqamah)
            .environment(app.log)
            .environment(app.quran)
            .environment(app.reading)
            .environment(app.navigation)
            .environment(app.scheduler)
            .environment(app.update)
    }
}
