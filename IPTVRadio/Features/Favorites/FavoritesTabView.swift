import SwiftUI

/// Favorites tab: only the stations the user has starred, nothing else.
struct FavoritesTabView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var playback: PlaybackEngine
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
                        ForEach(favorites.favorites.enumerated().map { IndexedFavorite(index: $0.offset, entry: $0.element) }) { item in
                            let entry = item.entry
                            HStack(spacing: 4) {
                                StationRow(station: entry.station)
                                if isReordering {
                                    ReorderButtons(
                                        name: entry.station.name,
                                        canMoveUp: item.index > 0,
                                        canMoveDown: item.index < favorites.favorites.count - 1,
                                        moveUp: { favorites.move(id: entry.id, by: -1) },
                                        moveDown: { favorites.move(id: entry.id, by: 1) }
                                    )
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        if !settings.liquidGlassEnabled {
                            Color.clear
                                .frame(height: 61 + (playback.state.station == nil ? 0 : 60))
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .accessibilityHidden(true)
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

private struct IndexedFavorite: Identifiable {
    let index: Int
    let entry: FavoritesStore.Entry
    var id: String { entry.id }
}
