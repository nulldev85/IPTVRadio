import SwiftUI

/// Library tab: favorites and recently played.
struct LibraryTabView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        NavigationStack {
            List {
                if !favorites.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites.favorites) { entry in
                            StationRow(station: entry.station)
                        }
                    }
                }
                if !history.entries.isEmpty {
                    Section("Recently Played") {
                        ForEach(history.entries.prefix(25)) { entry in
                            StationRow(station: entry.station)
                        }
                    }
                }
                if favorites.favorites.isEmpty && history.entries.isEmpty {
                    Section {
                        EmptyStateView(
                            title: "Nothing here yet",
                            message: "Stations you favorite and listen to will appear here.",
                            systemImage: "heart"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
        }
    }
}
