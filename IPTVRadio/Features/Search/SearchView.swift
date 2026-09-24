import SwiftUI

/// Search across station names, genres, categories and metadata.
struct SearchView: View {
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if library.state == .loaded {
                    searchContent
                } else {
                    LibraryStateView(state: library.state) {
                        Task { await library.refresh() }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $library.searchQuery, prompt: "Station, genre, show or category")
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let results = library.searchResults()
        if library.searchQuery.trimmingCharacters(in: .whitespaces).count < 2 {
            EmptyStateView(
                title: "Search your stations",
                message: "Type at least two characters to search by station name, genre, category or show metadata.",
                systemImage: "magnifyingglass"
            )
        } else if results.isEmpty {
            EmptyStateView(
                title: "No matches",
                message: "Nothing matched \"\(library.searchQuery)\".",
                systemImage: "questionmark.circle"
            )
        } else {
            List {
                ForEach(results) { station in
                    StationRow(station: station)
                }
            }
            .listStyle(.plain)
            .appScrollBackground()
        }
    }
}
