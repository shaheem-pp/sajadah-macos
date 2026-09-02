//
//  PrayerTimesStore.swift
//  Sajadah
//

import AppKit
import CoreLocation
import Foundation
import Observation

/// One prayer with everything scheduling a notification about it needs: which day it belongs
/// to (so an answered prayer can be skipped), when the Adhan is, and when the masjid's Iqamah
/// follows — `nil` when no masjid is configured, or its posted time can't be read.
nonisolated struct UpcomingPrayer: Identifiable, Sendable, Equatable {
    let prayer: Prayer
    let dayKey: String
    let adhan: Date
    let iqamah: Date?

    var id: String { "\(dayKey)-\(prayer.rawValue)" }
}

/// Owns prayer timings: fetching them, caching them to disk, and answering "what's next?".
///
/// Timings are cached a whole month at a time and always kept covering at least the next
/// eight days, which is what makes the next-prayer search work across midnight and gives the
/// notification scheduler a week to fill.
@Observable
final class PrayerTimesStore {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: Observed state

    private(set) var loadState: LoadState = .idle
    /// True when a refresh failed but cached timings are still being shown.
    private(set) var isStale = false
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var placeName: String?

    /// Advanced once a second by `Ticker`. Views that want a live countdown read this.
    private(set) var now: Date = .now

    /// What the menubar item should show. Reassigned only when it actually differs, so the
    /// status item redraws about once a minute instead of once a second.
    private(set) var menuBar: MenuBarContent = .placeholder

    /// The instant `menuBar` is counting down to — the next Adhan, or an Iqamah still ahead of
    /// it. Read by `Ticker` to work out when the displayed minute will actually change, so it
    /// can sleep until exactly then instead of sampling on a fixed cadence.
    ///
    /// Not observed: it moves with the countdown and would invalidate every view watching the
    /// store, once a tick, for a value no view reads.
    @ObservationIgnored private(set) var menuBarTarget: Date?

    private(set) var days: [String: DayTimings] = [:]

    /// Fires whenever the set of known future prayers changes, so notifications can be rescheduled.
    @ObservationIgnored var onEventsChanged: (() -> Void)?

    // MARK: Private state

    @ObservationIgnored private var fetchedMonths: Set<String> = []
    @ObservationIgnored private var sortedEvents: [PrayerEvent] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastSeenDayKey: String?
    /// The most recent Iqamah data `tick(_:iqamah:)` was handed, reused by `rebuildEvents()` so
    /// a data refresh doesn't momentarily forget it until the next tick corrects it.
    @ObservationIgnored private var lastIqamah: IqamahTimes?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private let api = AladhanAPI.shared

    /// How far the user must move before cached timings are considered wrong for them.
    private static let significantMoveMetres: CLLocationDistance = 5_000
    /// Days of coverage to keep ahead of today.
    private static let coverageDays = 8
    /// How far back `upcomingPrayers(limitDays:iqamah:)` still reports a prayer. Comfortably
    /// longer than the largest check-in delay the settings allow, so a just-passed Adhan keeps
    /// its follow-ups.
    private static let scheduleLookback: TimeInterval = 6 * 3_600

    // MARK: Init

    init() {
        loadCache()
        observeSystemEvents()
        lastSeenDayKey = DayKey.make(for: .now, in: displayTimeZone)
        rebuildEvents()
    }

    func configure(settings: AppSettings) {
        self.settings = settings

        // Timings computed with a different method are simply wrong now — drop them.
        if cachedMethod != settings.calculationMethod || cachedSchool != settings.asrSchool.rawValue {
            days = [:]
            fetchedMonths = []
            rebuildEvents()
        }
    }

    // MARK: Derived values

    var displayTimeZone: TimeZone {
        days[todayKeyInCurrentZone]?.timeZone
            ?? days.values.max { $0.dayKey < $1.dayKey }?.timeZone
            ?? .current
    }

    var today: DayTimings? {
        days[DayKey.make(for: now, in: displayTimeZone)]
    }

    var hijriDateText: String? { today?.hijri }

    /// The next actual prayer after `now`. Sunrise is skipped — it is a boundary, not a prayer.
    var nextEvent: PrayerEvent? {
        sortedEvents.first { $0.date > now && $0.prayer.isPrayer }
    }

    /// The most recent prayer that has already started, used to highlight "we're in Asr now".
    var currentEvent: PrayerEvent? {
        sortedEvents.last { $0.date <= now && $0.prayer.isPrayer }
    }

    var timeUntilNextEvent: TimeInterval? {
        nextEvent.map { $0.date.timeIntervalSince(now) }
    }

    /// Every prayer the notification scheduler might still have something to say about, with
    /// the day it belongs to and the masjid's Iqamah for it.
    ///
    /// The window reaches slightly *backwards* as well as forwards: a prayer whose Adhan was a
    /// few minutes ago still has a "did you pray?" ask ahead of it. Deciding which of a
    /// prayer's derived moments have already passed is the scheduler's job, so this hands over
    /// everything that could still matter and lets it drop what's spent.
    func upcomingPrayers(limitDays: Int, iqamah: IqamahSchedule?) -> [UpcomingPrayer] {
        let horizon = now.addingTimeInterval(Double(limitDays) * 86_400)
        let earliest = now.addingTimeInterval(-Self.scheduleLookback)

        return days.values
            .flatMap { day in
                DayLog.tracked.compactMap { prayer -> UpcomingPrayer? in
                    let adhan = day.time(for: prayer)
                    guard adhan > earliest, adhan <= horizon else { return nil }
                    return UpcomingPrayer(
                        prayer: prayer,
                        dayKey: day.dayKey,
                        adhan: adhan,
                        iqamah: iqamah?.date(for: prayer, on: day)
                    )
                }
            }
            .sorted { $0.adhan < $1.adhan }
    }

    var todayKey: String {
        DayKey.make(for: now, in: displayTimeZone)
    }

    /// The day's timings an instant falls inside, by the display timezone's calendar day.
    private func day(containing date: Date) -> DayTimings? {
        days[DayKey.make(for: date, in: displayTimeZone)]
    }

    // MARK: Day phase

    /// Where the clock sits in the day right now — see `DayPhase`.
    ///
    /// `iqamah` and `dayIsComplete` are handed in rather than read: this store owns neither the
    /// masjid scrape nor the user's log. Taking them as arguments keeps those dependencies
    /// visible to a reader, and to SwiftUI's observation at the call site.
    func phase(iqamah: IqamahTimes?, dayIsComplete: Bool) -> DayPhase {
        guard !sortedEvents.isEmpty else { return .unavailable }

        // An answered day outranks everything else. It can't be reached early: a prayer is
        // only loggable once its own time has come.
        if dayIsComplete { return .dayComplete(next: nextEvent) }

        // The same test the menubar retargets on, so the two can't disagree about whether a
        // jamaah is still ahead.
        if let waiting = waitingForIqamah(at: now, iqamah: iqamah) {
            return .awaitingIqamah(
                prayer: waiting.event.prayer,
                adhan: waiting.event.date,
                iqamah: waiting.iqamahDate
            )
        }

        // `currentEvent` can belong to yesterday — at 3am it's yesterday's Isha — which is
        // exactly why the window close is looked up on that event's own day rather than today's.
        let cutoff = settings?.ishaCutoffMinutes ?? AppSettings.defaultIshaCutoffMinutes
        if let current = currentEvent,
           let day = day(containing: current.date),
           let close = day.windowClose(for: current.prayer, ishaCutoffMinutes: cutoff),
           now < close {
            return .inWindow(prayer: current.prayer, adhan: current.date, closesAt: close)
        }

        return nextEvent.map { .awaitingAdhan(next: $0) } ?? .unavailable
    }

    /// Upcoming window closes, which is where check-in questions hang off.
    func upcomingCheckIns(limitDays: Int, ishaCutoffMinutes: Int) -> [PrayerCheckIn] {
        let horizon = now.addingTimeInterval(Double(limitDays) * 86_400)
        return days.values
            .flatMap { day in
                DayLog.tracked.compactMap { prayer -> PrayerCheckIn? in
                    guard let close = day.windowClose(for: prayer, ishaCutoffMinutes: ishaCutoffMinutes),
                          close > now, close <= horizon else { return nil }
                    return PrayerCheckIn(prayer: prayer, dayKey: day.dayKey, windowClose: close)
                }
            }
            .sorted { $0.windowClose < $1.windowClose }
    }

    func days(from start: Date, count: Int) -> [DayTimings] {
        let zone = displayTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return days[DayKey.make(for: date, in: zone)]
        }
    }

    // MARK: Ticking

    /// `iqamah` is whatever `IqamahStore.times` currently holds — `PrayerTimesStore` doesn't
    /// own or fetch it, just uses it to decide what the menubar should anchor on right now.
    func tick(_ date: Date, iqamah: IqamahTimes?) {
        now = date
        lastIqamah = iqamah

        let content = makeMenuBarContent(at: date, iqamah: iqamah)
        if content != menuBar { menuBar = content }

        let dayKey = DayKey.make(for: date, in: displayTimeZone)
        if dayKey != lastSeenDayKey {
            lastSeenDayKey = dayKey
            // A new day may need a new month fetched, and yesterday's notifications are spent.
            refresh()
            onEventsChanged?()
        }
    }

    /// `MenuBarContent` is `nonisolated` data and can't call the main-actor `TimeFormatting`
    /// itself, so clock strings are formatted here, on the way in.
    ///
    /// Normally this counts down to the next Adhan. But once some prayer's Adhan has passed and
    /// its Iqamah (per the masjid's posted time) hasn't, the display retargets to that Iqamah
    /// instead — one clock at a time, never both, since only one is actually the thing to wait
    /// for at any given moment.
    private func makeMenuBarContent(at date: Date, iqamah: IqamahTimes?) -> MenuBarContent {
        if let waiting = waitingForIqamah(at: date, iqamah: iqamah) {
            menuBarTarget = waiting.iqamahDate
            return MenuBarContent(
                icon: waiting.event.prayer.systemImage,
                prayer: waiting.event.prayer.displayName,
                countdown: MenuBarContent.countdownText(from: date, until: waiting.iqamahDate),
                clockTime: TimeFormatting.clock(
                    waiting.iqamahDate,
                    use24Hour: settings?.use24HourClock ?? false,
                    timeZone: displayTimeZone
                ),
                prayerCase: waiting.event.prayer,
                moment: .iqamah
            )
        }

        let next = nextEvent
        menuBarTarget = next?.date
        let clockTime = next.map {
            TimeFormatting.clock($0.date, use24Hour: settings?.use24HourClock ?? false, timeZone: displayTimeZone)
        } ?? ""
        return MenuBarContent(next: next, at: date, clockTime: clockTime)
    }

    private func waitingForIqamah(at date: Date, iqamah: IqamahTimes?) -> (event: PrayerEvent, iqamahDate: Date)? {
        guard let current = currentEvent, current.prayer.isPrayer,
              let iqamahDate = iqamah?.date(for: current.prayer, onSameDayAs: current.date, timeZone: displayTimeZone),
              date < iqamahDate
        else { return nil }
        return (current, iqamahDate)
    }

    // MARK: Location

    func updateCoordinate(_ new: CLLocationCoordinate2D) {
        let previous = coordinate
        coordinate = new

        let moved = previous.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: new.latitude, longitude: new.longitude))
        } ?? .greatestFiniteMagnitude

        if moved > Self.significantMoveMetres {
            days = [:]
            fetchedMonths = []
            placeName = nil
            rebuildEvents()
            resolvePlaceName(for: new)
        }
        refresh()
    }

    // MARK: Refresh

    /// Fetches whatever months are missing to keep `coverageDays` of timings ahead of today.
    /// `force: true` refetches even months already cached (used when the method changes).
    func refresh(force: Bool = false) {
        guard let coordinate else { return }
        let settings = settings

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }

            if force {
                days = [:]
                fetchedMonths = []
                rebuildEvents()
            }

            let wanted = requiredMonthKeys()
            let missing = wanted.filter { !self.fetchedMonths.contains($0) }
            guard !missing.isEmpty else {
                loadState = .loaded
                isStale = false
                return
            }

            if days.isEmpty { loadState = .loading }

            let method = settings?.calculationMethod ?? CalculationMethod.defaultID
            let school = settings?.asrSchool.rawValue ?? AsrSchool.standard.rawValue
            var fetchedAny = false
            var failure: String?

            for key in missing {
                guard !Task.isCancelled else { return }
                let parts = key.split(separator: "-")
                guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { continue }

                do {
                    let result = try await api.monthlyCalendar(
                        year: year,
                        month: month,
                        coordinate: coordinate,
                        method: method,
                        school: school
                    )
                    guard !Task.isCancelled else { return }
                    for day in result { days[day.dayKey] = day }
                    fetchedMonths.insert(key)
                    fetchedAny = true
                } catch {
                    failure = (error as? AladhanError)?.errorDescription ?? error.localizedDescription
                }
            }

            guard !Task.isCancelled else { return }

            if fetchedAny {
                pruneOldDays()
                rebuildEvents()
                persist(method: method, school: school)
                onEventsChanged?()
            }

            if let failure {
                // Keep showing whatever we have; a menubar that goes blank when the wifi
                // drops is worse than one that admits it is out of date.
                isStale = !days.isEmpty
                loadState = days.isEmpty ? .failed(failure) : .loaded
            } else {
                isStale = false
                loadState = .loaded
            }
        }
    }

    /// Wipes cached timings and refetches — for when the calculation method or school changes.
    func invalidateAndRefresh() {
        refresh(force: true)
    }

    private func requiredMonthKeys() -> [String] {
        let zone = displayTimeZone
        let horizon = now.addingTimeInterval(Double(Self.coverageDays) * 86_400)
        // Ordered, deduplicated: today's month first so the visible day loads soonest.
        var keys: [String] = []
        for key in [DayKey.month(for: now, in: zone), DayKey.month(for: horizon, in: zone)]
        where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private func rebuildEvents() {
        sortedEvents = days.values.flatMap(\.events).sorted { $0.date < $1.date }
        menuBar = makeMenuBarContent(at: now, iqamah: lastIqamah)
    }

    private func pruneOldDays() {
        let cutoff = DayKey.make(for: now.addingTimeInterval(-86_400), in: displayTimeZone)
        days = days.filter { $0.key >= cutoff }
        // A month whose days were partly pruned must not look fully cached any more.
        fetchedMonths = fetchedMonths.filter { $0 >= String(cutoff.prefix(7)) }
    }

    // MARK: Place name

    private func resolvePlaceName(for coordinate: CLLocationCoordinate2D) {
        Task { [weak self] in
            let name = await PlaceNameResolver.shortName(for: coordinate)
            guard let self, let name else { return }
            placeName = name
            persist(method: cachedMethod, school: cachedSchool)
        }
    }

    func refreshPlaceNameIfNeeded() {
        guard placeName == nil, let coordinate else { return }
        resolvePlaceName(for: coordinate)
    }

    // MARK: System events

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handleWakeOrClockChange() }
        }

        for name in [NSNotification.Name.NSCalendarDayChanged, .NSSystemClockDidChange] {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.handleWakeOrClockChange() }
            }
        }
    }

    private func handleWakeOrClockChange() {
        tick(.now, iqamah: lastIqamah)
        refresh()
        onEventsChanged?()
    }

    // MARK: Persistence

    @ObservationIgnored private var cachedMethod: Int = CalculationMethod.defaultID
    @ObservationIgnored private var cachedSchool: Int = AsrSchool.standard.rawValue

    private var cacheURL: URL? { AppFiles.url(for: CacheFileName.prayerTimes) }

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(PrayerCacheFile.self, from: data) else { return }

        days = cache.days
        fetchedMonths = Set(cache.fetchedMonths)
        placeName = cache.placeName
        cachedMethod = cache.method
        cachedSchool = cache.school
        if let latitude = cache.latitude, let longitude = cache.longitude {
            // Seeds the menubar with real times immediately, before CoreLocation answers.
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        pruneOldDays()
    }

    private func persist(method: Int, school: Int) {
        cachedMethod = method
        cachedSchool = school

        let cache = PrayerCacheFile(
            days: days,
            fetchedMonths: Array(fetchedMonths),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            placeName: placeName,
            method: method,
            school: school
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        AppFiles.write(data, to: CacheFileName.prayerTimes)
    }

    private var todayKeyInCurrentZone: String {
        DayKey.make(for: now, in: .current)
    }
}
