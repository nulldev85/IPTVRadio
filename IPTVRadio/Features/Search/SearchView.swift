import SwiftUI

/// Search across station names, genres, categories and metadata.
struct SearchView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var manualStations: ManualStationStore

    var body: some View {
        NavigationStack {
            ZStack {
                AetherTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Group {
                        if library.state == .loaded || !manualStations.entries.isEmpty {
                            searchContent
                        } else {
                            LibraryStateView(state: library.state) {
                                Task { await library.refresh() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Search")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .background(AetherTheme.background.ignoresSafeArea())
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AetherTheme.mutedIcon)
            TextField("", text: $library.searchQuery,
                      prompt: Text("Station, genre, show or category")
                        .foregroundStyle(AetherTheme.mutedIcon))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AetherTheme.secondaryText)
                .accessibilityIdentifier("search.field")
            if !library.searchQuery.isEmpty {
                Button {
                    library.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AetherTheme.mutedIcon)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(AetherTheme.raisedSurface, in: Capsule())
        .overlay(Capsule().stroke(AetherTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var searchContent: some View {
        let query = library.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.count < 2 {
            EmptyStateView(
                title: "Search your stations",
                message: "Type at least two characters to search by station name, genre, category or show metadata.",
                systemImage: "magnifyingglass"
            )
        } else {
            let manualResults = manualStations.entries.lazy.map(\.station).filter {
                $0.name.lowercased().contains(query) || $0.groupTitle.lowercased().contains(query)
            }
            let results = (library.state == .loaded ? library.searchResults() : []) + Array(manualResults)
            if results.isEmpty {
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
}
