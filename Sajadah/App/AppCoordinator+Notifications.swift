//
//  AppCoordinator+Notifications.swift
//  Sajadah
//

import Foundation
import WidgetKit

extension AppCoordinator {
    /// How far ahead notifications are scheduled. Three kinds per prayer plus the closing ask
    /// is around twenty a day against macOS's 64-request budget, so a longer horizon would only
    /// build candidates that get trimmed away unscheduled.
    private static let scheduleHorizonDays = 3

    /// How long the batch may go untouched before the ticker rebuilds it anyway.
    private static let scheduleTopUpInterval: TimeInterval = 30 * 60

    /// Everything the pending batch is derived from, and what a change to any of it has to
    /// reach.
    ///
    /// Widgets ride along here rather than in a file of their own: they read the same cache
    /// the scheduler does, and each of these changes moves something a widget shows, so the
    /// hook that rebuilds the batch is also the one that reloads the timelines.
    func wireNotifications() {
        settings.onNotificationPreferencesChanged = { [weak self] in
            guard let self else { return }
            rescheduleNotifications()
            // The Isha cutoff is among these, and it decides when a widget stops saying "in
            // the window". The cache is the only route to the widget, so rewrite it — cheap,
            // and the other preferences in this group change rarely enough not to matter.
            store.syncPreferencesToCache()
            WidgetCenter.shared.reloadAllTimelines()
        }
        store.onEventsChanged = { [weak self] in
            self?.rescheduleNotifications()
            WidgetCenter.shared.reloadAllTimelines()
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
            guard let self else { return }
            rescheduleNotifications()
            // Logging the prayer in progress moves the menubar off its jamaah, and the ticker
            // may be a minute from looking on its own.
            store.tick(.now, iqamah: iqamah.times, log: log.days)
            // Widgets read the cache rather than polling, so they need telling it moved.
            WidgetCenter.shared.reloadAllTimelines()
        }
        scheduler.onCheckInResponse = { [log] prayer, dayKey, state in
            log.set(state, for: prayer, on: dayKey)
        }
        scheduler.onOpenSurah = { [navigation] surah in
            navigation.openSurah(surah)
        }
    }

    /// Rebuilds the pending notifications, coalescing bursts.
    ///
    /// Dragging a stepper in Settings fires this on every step, and each rebuild is several
    /// round trips to the notification daemon. The short delay collapses that into one pass;
    /// the scheduler serialises whatever still overlaps.
    func rescheduleNotifications() {
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
    func topUpNotificationsIfStale(at date: Date) {
        guard let last = lastRescheduledAt else { return }
        guard date.timeIntervalSince(last) > Self.scheduleTopUpInterval else { return }
        rescheduleNotifications()
    }
}
