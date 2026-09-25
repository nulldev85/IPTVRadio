import SwiftUI

/// Search across station names, genres, categories and metadata.
struct SearchView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var manualStations: ManualStationStore

    var body: some View {
        NavigationStack {
            Group {
                if library.state == .loaded || !manualStations.entries.isEmpty {
                    searchContent
                } else {
                    LibraryStateView(state: library.state) {
                        Task { await library.refresh() }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $library.searchQuery, prompt: "Station, genre, show or category")
            .background(AetherTheme.background.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let query = library.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let manualResults = manualStations.entries.map(\.station).filter {
            $0.name.lowercased().contains(query) || $0.groupTitle.lowercased().contains(query)
        }
        let results = (library.state == .loaded ? library.searchResults() : []) + manualResults
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
            .scrollContentBackground(.hidden)
        }
    }
}
