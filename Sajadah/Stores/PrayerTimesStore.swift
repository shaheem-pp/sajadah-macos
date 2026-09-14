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

/// A voluntary fasting day with what a reminder about it needs: why it is one, when Fajr is,
/// and the evening before it — which is where the reminder belongs, since a fast is decided
/// on the night before. As with Iqamah, *when* to fire is the scheduler's call.
nonisolated struct FastingDay: Identifiable, Sendable, Equatable {
    let dayKey: String
    let hijri: HijriDate
    let reasons: [FastingReason]
    let fajr: Date
    let eve: DayTimings

    var id: String { dayKey }
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

    /// The timings every reader uses, with the user's Adhan adjustments applied. Derived from
    /// `rawDays` in `rebuildEvents()`; nothing writes to it directly.
    private(set) var days: [String: DayTimings] = [:]

    /// Fires whenever the set of known future prayers changes, so notifications can be rescheduled.
    @ObservationIgnored var onEventsChanged: (() -> Void)?

    // MARK: Private state

    /// The timings as the API computed them — what the cache holds. Adjustments are applied on
    /// the way out rather than baked in, so changing them is arithmetic, not a refetch.
    @ObservationIgnored private var rawDays: [String: DayTimings] = [:]
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
            rawDays = [:]
            fetchedMonths = []
        }
        // Unconditionally: `init` derived `days` before there were settings to adjust by.
        rebuildEvents()
    }

    /// Re-derives every reader's timings from the cached ones. The cache is rewritten so the
    /// widget sees the same adjustment, and `onEventsChanged` moves the notifications.
    func adhanAdjustmentsChanged() {
        rebuildEvents()
        if !rawDays.isEmpty { persist(method: cachedMethod, school: cachedSchool) }
        onEventsChanged?()
    }

    // MARK: Derived values

    var displayTimeZone: TimeZone {
        // Off the raw cache: `loadCache` asks before the first `rebuildEvents` has derived
        // `days`, and an adjustment never changes a day's zone anyway.
        rawDays[todayKeyInCurrentZone]?.timeZone
            ?? rawDays.values.max { $0.dayKey < $1.dayKey }?.timeZone
            ?? .current
    }

    var today: DayTimings? {
        days[DayKey.make(for: now, in: displayTimeZone)]
    }

    /// The Hijri date of the civil day `dayKey`, with the user's adjustment applied.
    func hijriDate(for dayKey: String) -> HijriDate? {
        days.hijriDate(for: dayKey, adjustedBy: settings?.hijriAdjustmentDays ?? 0, timeZone: displayTimeZone)
    }

    /// What the date line reads right now — adjusted, and past Maghrib already tomorrow's.
    var displayedHijriDate: HijriDate? {
        days.displayedHijriDate(
            at: now,
            preferences: settings?.hijriPreferences ?? HijriPreferences(),
            timeZone: displayTimeZone
        )
    }

    /// Falls back to the API's own string for a cache written before the structured date
    /// existed, so the line never goes blank while the one-time refetch is in flight.
    var hijriDateText: String? { displayedHijriDate?.formatted ?? today?.hijri }

    /// "Fasting day · Monday", "Iftar 7:32 PM", or nil. Lives beside the Hijri date it is
    /// derived from, and is worded here rather than in the calendar because one case carries
    /// a clock time, which only the app knows how the user wants written.
    var fastingIndicator: String? {
        guard let settings else { return nil }
        let indicator = days.fastingIndicator(
            at: now,
            hijri: settings.hijriPreferences,
            fasting: settings.fastingPreferences,
            timeZone: displayTimeZone
        )
        return switch indicator {
        case .fastingToday(let reasons): "Fasting day · \(reasons.joined)"
        case .fastingTomorrow(let reasons): "Fasting tomorrow · \(reasons.joined)"
        case .iftar(let maghrib):
            "Iftar \(TimeFormatting.clock(maghrib, use24Hour: settings.use24HourClock, timeZone: displayTimeZone))"
        case .ramadanTomorrow: "Ramadan tomorrow"
        case nil: nil
        }
    }

    /// The civil day `dayKey`'s fasting status, on the adjusted Hijri date. Nil with fasting off.
    func fastingStatus(on dayKey: String) -> FastingDayStatus? {
        guard let settings else { return nil }
        return days.fastingStatus(
            on: dayKey,
            hijri: settings.hijriPreferences,
            fasting: settings.fastingPreferences,
            timeZone: displayTimeZone
        )
    }

    /// Fasting days from today through `limitDays` ahead, for listing rather than reminding.
    /// Runs past the cached days: the weekday needs no timings and the Hijri date falls back
    /// to arithmetic, so the list is the same length whichever month the cache ends in.
    func fastingDays(withinDays limitDays: Int) -> [FastingDayStatus] {
        let todayKey = todayKey
        return (0...limitDays).compactMap { offset in
            guard let key = DayKey.shifted(todayKey, by: offset),
                  let status = fastingStatus(on: key), status.isFast else { return nil }
            return status
        }
    }

    /// Fasting days within `limitDays` of today whose reminder could still fire. Starts at
    /// today rather than tomorrow: today's evening-before has passed, but a fixed reminder
    /// time after midnight hasn't necessarily, and the scheduler drops what's spent. A day
    /// whose reasons don't want an eve reminder — every Ramadan day but the first — is left out.
    func upcomingFastingDays(limitDays: Int) -> [FastingDay] {
        guard let settings, settings.fastingEnabled else { return [] }
        let todayKey = todayKey
        return (0...limitDays).compactMap { offset in
            guard let key = DayKey.shifted(todayKey, by: offset), let day = days[key],
                  let eveKey = DayKey.previous(key), let eve = days[eveKey],
                  let status = fastingStatus(on: key),
                  status.reasons.contains(where: { $0.remindsOnEve(of: status.hijri) }) else { return nil }
            return FastingDay(dayKey: key, hijri: status.hijri, reasons: status.reasons, fajr: day.fajr, eve: eve)
        }
    }

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
        // The rule itself lives with `DayPhase`, where the widget snapshot reaches it too.
        DayPhase.resolve(
            at: now,
            events: sortedEvents,
            days: days,
            timeZone: displayTimeZone,
            iqamah: iqamah,
            ishaCutoffMinutes: settings?.ishaCutoffMinutes ?? AppSettings.defaultIshaCutoffMinutes,
            dayIsComplete: dayIsComplete
        )
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
            rawDays = [:]
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
                rawDays = [:]
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

            if rawDays.isEmpty { loadState = .loading }

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
                    for day in result { rawDays[day.dayKey] = day }
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
                isStale = !rawDays.isEmpty
                loadState = rawDays.isEmpty ? .failed(failure) : .loaded
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
        days = rawDays.adjusted(by: settings?.adhanAdjustments ?? PrayerAdjustments())
        sortedEvents = days.values.flatMap(\.events).sorted { $0.date < $1.date }
        menuBar = makeMenuBarContent(at: now, iqamah: lastIqamah)
    }

    private func pruneOldDays() {
        // Three days back rather than one: a Hijri adjustment of −2 reads today's date off
        // the day before yesterday's entry, and a pruned entry means a computed fallback that
        // may not match the API's.
        let cutoff = DayKey.make(for: now.addingTimeInterval(-3 * 86_400), in: displayTimeZone)
        rawDays = rawDays.filter { $0.key >= cutoff }
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

        rawDays = cache.days
        fetchedMonths = Set(cache.fetchedMonths)
        placeName = cache.placeName
        // A cache from before the structured Hijri date existed has the string and nothing
        // else. Forgetting the months were fetched makes the next refresh fetch them again —
        // once — and overwrite each day in place. Only days from today on count: a refresh
        // never refetches last month, so a leftover from it would trip this every launch.
        let today = DayKey.make(for: now, in: displayTimeZone)
        if rawDays.contains(where: { $0.key >= today && $0.value.hijriDate == nil }) {
            fetchedMonths = []
        }
        cachedMethod = cache.method
        cachedSchool = cache.school
        if let latitude = cache.latitude, let longitude = cache.longitude {
            // Seeds the menubar with real times immediately, before CoreLocation answers.
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        pruneOldDays()
    }

    /// Rewrites the cache with the current preferences and nothing else changed. The widget
    /// reads its copy of this file, not defaults, so a preference has to be written here to
    /// reach it at all.
    func syncPreferencesToCache() {
        guard !rawDays.isEmpty else { return }
        persist(method: cachedMethod, school: cachedSchool)
    }

    private func persist(method: Int, school: Int) {
        cachedMethod = method
        cachedSchool = school

        let cache = PrayerCacheFile(
            days: rawDays,
            fetchedMonths: Array(fetchedMonths),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            placeName: placeName,
            method: method,
            school: school,
            hijri: settings?.hijriPreferences,
            fasting: settings?.fastingPreferences,
            adjustments: settings?.adhanAdjustments,
            ishaCutoffMinutes: settings?.ishaCutoffMinutes
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
