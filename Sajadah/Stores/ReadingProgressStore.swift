//
//  ReadingProgressStore.swift
//  Sajadah
//

import Foundation
import Observation

/// Bookmarks and where you left off.
///
/// Its own file, for the same reason `PrayerLogStore` has one: this is the user's own data and
/// must survive the text cache being thrown away when a translation changes.
@Observable
final class ReadingProgressStore {

    private(set) var bookmarks: Set<AyahRef> = []
    private(set) var lastRead: AyahRef?

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        load()
    }

    // MARK: Bookmarks

    func isBookmarked(_ ref: AyahRef) -> Bool {
        bookmarks.contains(ref)
    }

    func toggleBookmark(_ ref: AyahRef) {
        if bookmarks.contains(ref) {
            bookmarks.remove(ref)
        } else {
            bookmarks.insert(ref)
        }
        scheduleSave()
    }

    /// Bookmarks in recitation order, for listing.
    var sortedBookmarks: [AyahRef] {
        bookmarks.sorted { ($0.surah, $0.ayah) < ($1.surah, $1.ayah) }
    }

    // MARK: Position

    /// Called as the reader scrolls, so writes are coalesced rather than hitting disk per row.
    func recordPosition(_ ref: AyahRef) {
        guard lastRead != ref else { return }
        lastRead = ref
        scheduleSave()
    }

    // MARK: Persistence

    private struct Stored: Codable {
        var bookmarks: [AyahRef]
        var lastRead: AyahRef?
    }

    private func load() {
        guard let url = AppFiles.url(for: "quran-progress.json"),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        bookmarks = Set(stored.bookmarks)
        lastRead = stored.lastRead
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard let url = AppFiles.url(for: "quran-progress.json"),
              let data = try? JSONEncoder().encode(
                  Stored(bookmarks: sortedBookmarks, lastRead: lastRead)
              ) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
