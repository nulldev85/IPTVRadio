import SwiftUI

/// Favorites tab: only the stations the user has starred, nothing else.
struct FavoritesTabView: View {
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        NavigationStack {
            Group {
                if favorites.favorites.isEmpty {
                    EmptyStateView(
                        title: "No favorites yet",
                        message: "Tap the star on any station to keep it here.",
                        systemImage: "heart"
                    )
                } else {
                    List {
                        ForEach(favorites.favorites) { entry in
                            StationRow(station: entry.station)
                        }
                    }
                    // Plain, like every other station list: inset-grouped cards
                    // put a second surface under rows that already carry one.
                    .listStyle(.plain)
                    .appScrollBackground()
                }
            }
            .navigationTitle("Favorites")
        }
    }
}
