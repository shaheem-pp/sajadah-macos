//
//  AppCoordinator.swift
//  Sajadah
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// Owns the app's long-lived objects and wires them together.
///
/// This exists because the connections between them have to hold whether or not any view is
/// on screen — the menubar keeps counting down with the popover closed and no window open.
///
/// The wiring is split by concern across the `AppCoordinator+*.swift` files, so a change to
/// how notifications follow the prayer log and one to how timings follow the location don't
/// land in the same lines. This file keeps what every concern shares: the objects, the order
/// they come up in, and the ticker that drives them all.
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

    // An extension can't declare stored properties, so the state a concern file owns is
    // declared here and left internal for it. Nothing outside the coordinator reads these.

    // AppCoordinator+Widgets
    @ObservationIgnored var inboxWatcher: WidgetInboxWatcher?

    // AppCoordinator+Notifications
    @ObservationIgnored var rescheduleTask: Task<Void, Never>?
    @ObservationIgnored var lastRescheduledAt: Date?

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

        wirePrayerTimes()
        wireNotifications()
        wireQuran()
        // After the notification hooks: merging the inbox fires `log.onChange`, and a prayer
        // logged from a widget while the app was closed has to reach the scheduler and the
        // widgets like any other.
        startWidgetInbox()
        startTicker()

        // Sajadah is a menubar app: no window open, no Dock icon.
        DockVisibility.start()

        observeActivation()

        Task { [weak self] in await self?.start() }
    }

    private func startTicker() {
        ticker = Ticker(countdownTarget: { [store] in store.menuBarTarget }) { [weak self, store, quran, iqamah, log] date in
            store.tick(date, iqamah: iqamah.times, log: log.days)
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
                // A tap the directory watcher missed — it wasn't running yet, or the
                // container appeared after launch — is caught here at the latest.
                self.log.mergeWidgetInbox()
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
