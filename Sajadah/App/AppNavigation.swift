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

/// Where the main window is pointed. Lives outside the view tree so the menubar popover and
/// notification taps can steer it even when no window is open yet.
@Observable
final class AppNavigation {
    var selection: SidebarItem? = .today
    /// Set alongside `selection` to scroll the reader to a specific ayah.
    var scrollTarget: AyahRef?

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
