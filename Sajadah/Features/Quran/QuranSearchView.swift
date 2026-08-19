//
//  QuranSearchView.swift
//  Sajadah
//

import SwiftUI

/// Full-text search over the chosen translation. Kept separate from the sidebar's surah
/// filter: one is a remote text search, the other an instant local name filter, and merging
/// them into a single field makes both confusing.
struct QuranSearchView: View {
    @Environment(QuranStore.self) private var quran
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    let onOpen: (AyahRef) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search the translation…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onChange(of: query) { quran.search(query) }
            if !query.isEmpty {
                Button {
                    query = ""
                    quran.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var results: some View {
        switch quran.searchState {
        case .idle:
            ContentUnavailableView {
                Label("Search the Quran", systemImage: "magnifyingglass")
            } description: {
                Text("Find any phrase in \(QuranTranslation.name(for: settings.translationEdition)).")
            }

        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("Search failed", systemImage: "wifi.slash")
            } description: {
                Text(message)
            }

        case .loaded where quran.searchResults.isEmpty:
            ContentUnavailableView.search(text: quran.lastSearchQuery)

        case .loaded:
            List(quran.searchResults) { match in
                Button {
                    onOpen(match.ref)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(match.surahEnglishName) \(match.ref.surah):\(match.ref.ayah)")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(match.text)
                            .font(.system(size: settings.translationFontSize))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("\(quran.searchResults.count) result\(quran.searchResults.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }
}
