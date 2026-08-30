//
//  MenuBarContentView.swift
//  Sajadah
//

import AppKit
import SwiftUI

/// The popover behind the menubar item.
///
/// A narrower reading of the same day the main window shows: the hero answers the question,
/// the rows carry the detail, and everything below is one glance deep.
struct MenuBarContentView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(LocationManager.self) private var location
    @Environment(PrayerLogStore.self) private var log
    @Environment(QuranStore.self) private var quran
    @Environment(IqamahStore.self) private var iqamah
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let day = store.today {
                hero
                iqamahRow
                timings(day)
                streakRow

                if let daily = quran.dailyAyah {
                    Divider().overlay(Theme.hairline)
                    AyahOfTheDayView(
                        ayah: daily,
                        arabicFont: settings.arabicFontName,
                        onOpen: { openReader(at: daily.ref) }
                    )
                }
            } else {
                unavailableContent
            }

            Divider().overlay(Theme.hairline)
            actions
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if let next = store.nextEvent, let remaining = store.timeUntilNextEvent {
            NextPrayerHero(
                prayer: next.prayer,
                countdown: TimeFormatting.countdown(remaining),
                clock: TimeFormatting.clock(
                    next.date,
                    use24Hour: settings.use24HourClock,
                    timeZone: store.displayTimeZone
                ),
                place: store.placeName ?? "Current location",
                hijri: store.hijriDateText,
                isStale: store.isStale,
                progress: windowProgress,
                compact: true
            )
        } else {
            Text("No upcoming prayer times")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var windowProgress: Double? {
        guard let current = store.currentEvent, let next = store.nextEvent else { return nil }
        let span = next.date.timeIntervalSince(current.date)
        guard span > 0 else { return nil }
        return store.now.timeIntervalSince(current.date) / span
    }

    // MARK: Iqamah

    /// One line, not all five — the popover stays a glance deep. Uses `store.menuBar`'s already
    /// resolved anchor prayer rather than `store.nextEvent` directly — those differ exactly
    /// when some prayer's Adhan has passed but its Iqamah hasn't, and `nextEvent` alone would
    /// silently skip ahead to the following prayer and drop the still-upcoming Iqamah. Only
    /// appears once a masjid is configured in Settings.
    @ViewBuilder
    private var iqamahRow: some View {
        if let prayer = store.menuBar.prayerCase, let value = iqamah.times?.time(for: prayer) {
            HStack(spacing: 7) {
                Image(systemName: "building.columns")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.jade)

                Text("Iqamah")
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.wellFill, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        }
    }

    // MARK: Timings

    private func timings(_ day: DayTimings) -> some View {
        PrayerListView(
            day: day,
            highlighted: store.nextEvent?.prayer,
            passedBefore: store.now,
            use24Hour: settings.use24HourClock,
            logging: PrayerLogging(
                state: { log.state(for: $0, on: store.todayKey) },
                cycle: { log.cycle($0, on: store.todayKey) }
            ),
            compact: true
        )
    }

    private var streakRow: some View {
        let streak = log.currentStreak(asOf: store.todayKey)
        let prayed = log.prayedCount(on: store.todayKey)

        return HStack(spacing: 7) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 11))
                .foregroundStyle(streak > 0 ? Theme.brass : .secondary)

            Text(streak == 1 ? "1 day streak" : "\(streak) day streak")
                .fontWeight(.medium)

            Spacer(minLength: 8)

            Text("\(prayed)/\(DayLog.tracked.count) today")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(CalculationMethod.name(for: settings.calculationMethod))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 74, alignment: .trailing)
                .help(CalculationMethod.name(for: settings.calculationMethod))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.wellFill, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
    }

    // MARK: Empty / error states

    @ViewBuilder
    private var unavailableContent: some View {
        Group {
            switch location.state {
            case .needPermission:
                LocationPermissionView(onRequest: { location.requestPermission() })
            case .denied:
                LocationDeniedView(
                    onOpenSettings: { Self.openLocationSystemSettings() },
                    onRetry: { location.requestPermission() }
                )
            case .error(let message):
                LocationErrorView(message: message, onRetry: { location.refresh() })
            case .loading, .home:
                switch store.loadState {
                case .failed(let message):
                    LocationErrorView(message: message, onRetry: { store.refresh() })
                default:
                    LoadingView()
                }
            }
        }
        .frame(height: 190)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                store.refresh(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Fetch prayer times again")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Sajadah settings")

            Button {
                navigation.openToday()
                showWindow()
            } label: {
                Label("Window", systemImage: "macwindow")
            }
            .help("Open the full window")

            Button {
                navigation.selection = .quranSearch
                showWindow()
            } label: {
                Label("Quran", systemImage: "book")
            }
            .help("Open the Quran reader")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .help("Quit Sajadah")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.accessoryBar)
    }

    private func openReader(at ref: AyahRef) {
        navigation.open(ref)
        showWindow()
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: SajadahWindow.main)
    }

    static func openLocationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
