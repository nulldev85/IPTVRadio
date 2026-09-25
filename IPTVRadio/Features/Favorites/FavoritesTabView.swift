import SwiftUI

/// Favorites tab: only the stations the user has starred, nothing else.
struct FavoritesTabView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var isReordering = false

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
                            let index = favorites.favorites.firstIndex(where: { $0.id == entry.id }) ?? 0
                            HStack(spacing: 4) {
                                StationRow(station: entry.station)
                                if isReordering {
                                    ReorderButtons(
                                        name: entry.station.name,
                                        canMoveUp: index > 0,
                                        canMoveDown: index < favorites.favorites.count - 1,
                                        moveUp: { favorites.move(id: entry.id, by: -1) },
                                        moveDown: { favorites.move(id: entry.id, by: 1) }
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                if favorites.favorites.count > 1 || isReordering {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isReordering.toggle()
                        } label: {
                            if isReordering {
                                Text("Done")
                            } else {
                                Image(systemName: "arrow.up.arrow.down")
                                    .foregroundStyle(AetherTheme.mutedIcon)
                            }
                        }
                        .accessibilityLabel(isReordering ? "Done reordering" : "Reorder favorites")
                        .accessibilityIdentifier("favorites.reorder")
                    }
                }
            }
            .background(AetherTheme.background.ignoresSafeArea())
        }
    }
}
