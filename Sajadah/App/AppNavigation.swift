//
//  AppNavigation.swift
//  Sajadah
//

import Observation

nonisolated enum SidebarItem: Hashable, Sendable {
    case today
    case quranSearch
    case bookmarks
    case surah(Int)
}

/// One pane of the Settings window. `String`-backed so the last-used pane could be persisted
/// later without a migration.
nonisolated enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case notifications
    case fasting
    case quran
    case location
    case masjid
    case advanced

    var id: String { rawValue }
}

/// Where the main window is pointed. Lives outside the view tree so the menubar popover and
/// notification taps can steer it even when no window is open yet.
@Observable
final class AppNavigation {
    var selection: SidebarItem? = .today
    /// Set alongside `selection` to scroll the reader to a specific ayah.
    var scrollTarget: AyahRef?
    /// Which Settings pane is showing. Lives here for the same reason `selection` does: an
    /// invite in the window or popover sets it and *then* opens Settings, so it has to be
    /// settable before that window exists. It also carries the last-used pane across closes.
    var settingsPane: SettingsPane = .general

    /// Whether the main window shows its sidebar. Collapsed by default: the window opens on
    /// today's times, which have no use for a list of surahs beside them. Steering the window
    /// into the Quran — from the popover, a notification, a widget, or the verse on the Today
    /// page — shows it, because a reader with no way to the next surah is a dead end. The
    /// window's own toggle writes back here, so a choice made in the window carries across
    /// closes the way `settingsPane` does. Picking a row in the sidebar itself leaves it alone.
    var sidebarShown = false

    func openToday() {
        selection = .today
        scrollTarget = nil
        sidebarShown = false
    }

    func openQuranSearch() {
        selection = .quranSearch
        scrollTarget = nil
        sidebarShown = true
    }

    func open(_ ref: AyahRef) {
        selection = .surah(ref.surah)
        scrollTarget = ref
        sidebarShown = true
    }

    func openSurah(_ number: Int) {
        selection = .surah(number)
        scrollTarget = nil
        sidebarShown = true
    }
}
