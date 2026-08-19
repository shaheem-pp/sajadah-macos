//
//  MainWindowView.swift
//  Sajadah
//

import SwiftUI

/// The main window: prayer times and the Quran in one place.
struct MainWindowView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(QuranStore.self) private var quran
    @Environment(ReadingProgressStore.self) private var reading

    @State private var surahFilter = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detail
        }
        .task { quran.loadSurahList() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var navigation = navigation

        return List(selection: $navigation.selection) {
            Section("Prayer") {
                Label("Today", systemImage: "moon.stars")
                    .tag(SidebarItem.today)
            }

            Section("Quran") {
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.quranSearch)

                Label("Bookmarks", systemImage: "bookmark")
                    .badge(reading.bookmarks.count)
                    .tag(SidebarItem.bookmarks)

                if let last = reading.lastRead, let surah = quran.surah(numbered: last.surah) {
                    Button {
                        navigation.open(last)
                    } label: {
                        Label("Continue \(surah.englishName) \(last.ayah)", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Surahs") {
                ForEach(filteredSurahs) { surah in
                    SurahRow(surah: surah)
                        .tag(SidebarItem.surah(surah.number))
                }
            }
        }
        // A local, instant filter over 114 names — distinct from the remote text search above.
        .searchable(text: $surahFilter, placement: .sidebar, prompt: "Filter surahs")
    }

    private var filteredSurahs: [Surah] {
        let query = surahFilter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? quran.surahs : quran.surahs.filter { $0.matches(query) }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .today, nil:
            PrayerDetailView()

        case .quranSearch:
            QuranSearchView { navigation.open($0) }
                .navigationTitle("Search")

        case .bookmarks:
            BookmarksView { navigation.open($0) }
                .navigationTitle("Bookmarks")

        case .surah(let number):
            SurahReaderView(
                surahNumber: number,
                scrollTarget: navigation.scrollTarget?.surah == number
                    ? navigation.scrollTarget?.ayah
                    : nil
            )
            .navigationTitle(quran.surah(numbered: number)?.englishName ?? "Surah \(number)")
        }
    }
}

// MARK: - Rows

private struct SurahRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 8) {
            Text("\(surah.number)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(surah.englishName)
                Text(surah.englishNameTranslation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text(surah.name)
                .font(.arabic("Geeza Pro", size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Bookmarks

struct BookmarksView: View {
    @Environment(QuranStore.self) private var quran
    @Environment(ReadingProgressStore.self) private var reading

    let onOpen: (AyahRef) -> Void

    var body: some View {
        if reading.bookmarks.isEmpty {
            ContentUnavailableView {
                Label("No bookmarks", systemImage: "bookmark")
            } description: {
                Text("Click the bookmark beside any ayah while reading to save your place here.")
            }
        } else {
            List(reading.sortedBookmarks) { ref in
                Button {
                    onOpen(ref)
                } label: {
                    HStack {
                        Text(quran.surah(numbered: ref.surah)?.englishName ?? "Surah \(ref.surah)")
                        Text("\(ref.surah):\(ref.ayah)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Button {
                            reading.toggleBookmark(ref)
                        } label: {
                            Image(systemName: "bookmark.slash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove bookmark")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
