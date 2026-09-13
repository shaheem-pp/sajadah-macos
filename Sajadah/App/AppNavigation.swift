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
    case quran
    case location
    case masjid

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

    func openToday() {
        selection = .today
        scrollTarget = nil
    }

    func open(_ ref: AyahRef) {
        selection = .surah(ref.surah)
        scrollTarget = ref
    }

    func openSurah(_ number: Int) {
        selection = .surah(number)
        scrollTarget = nil
    }
}
