//
//  MenuBarContentView.swift
//  Sajadah
//

import AppKit
import SwiftUI

/// The popover behind the menubar item.
struct MenuBarContentView: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(LocationManager.self) private var location
    @Environment(PrayerLogStore.self) private var log
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = store.today {
                nextPrayerHeader
                Divider().padding(.vertical, 8)
                PrayerListView(
                    day: day,
                    highlighted: store.nextEvent?.prayer,
                    passedBefore: store.now,
                    use24Hour: settings.use24HourClock,
                    logging: PrayerLogging(
                        state: { log.state(for: $0, on: store.todayKey) },
                        cycle: { log.cycle($0, on: store.todayKey) }
                    )
                )
                Divider().padding(.vertical, 8)
                streakRow
                Divider().padding(.vertical, 8)
                placeFooter
            } else {
                unavailableContent
            }

            Divider().padding(.vertical, 8)
            actions
        }
        .padding(12)
        .frame(width: 288)
    }

    // MARK: Header

    private var nextPrayerHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Next prayer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isStale {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let next = store.nextEvent, let remaining = store.timeUntilNextEvent {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(next.prayer.displayName)
                        .font(.system(size: 22, weight: .semibold))
                    Text("in \(TimeFormatting.countdown(remaining))")
                        .font(.system(size: 15, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                Text(TimeFormatting.clock(
                    next.date,
                    use24Hour: settings.use24HourClock,
                    timeZone: store.displayTimeZone
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("No upcoming prayer times")
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }

    private var streakRow: some View {
        let streak = log.currentStreak(asOf: store.todayKey)
        let prayed = log.prayedCount(on: store.todayKey)

        return HStack(spacing: 6) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .foregroundStyle(streak > 0 ? .orange : .secondary)
            Text(streak == 1 ? "1 day streak" : "\(streak) day streak")
                .fontWeight(.medium)
            Spacer()
            Text("\(prayed)/\(DayLog.tracked.count) today")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
    }

    private var placeFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(store.placeName ?? "Current location", systemImage: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let hijri = store.hijriDateText {
                Text(hijri)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(CalculationMethod.name(for: settings.calculationMethod))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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
        .frame(height: 150)
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
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SajadahWindow.main)
            } label: {
                Label("Window", systemImage: "macwindow")
            }
            .help("Open the full prayer times window")

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

    static func openLocationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
