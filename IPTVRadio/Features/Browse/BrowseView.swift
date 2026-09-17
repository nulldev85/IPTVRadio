import SwiftUI

/// Category/genre browsing.
struct BrowseView: View {
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch library.state {
                case .loaded:
                    categoryList
                default:
                    LibraryStateView(state: library.state) {
                        Task { await library.refresh() }
                    }
                }
            }
            .navigationTitle("Browse")
            .refreshable {
                await library.refresh()
            }
        }
    }

    private var categoryList: some View {
        let categories = library.categories
        if categories.isEmpty {
            return AnyView(
                EmptyStateView(
                    title: "No categories",
                    message: "Your provider did not report any groups for the detected radio stations.",
                    systemImage: "square.grid.2x2"
                )
            )
        }
        return AnyView(
            List {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryStationsView(category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .font(.body)
                            Text("\(count(category)) stations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("browse.category.\(category.name)")
                }
            }
            .listStyle(.plain)
        )
    }

    private func count(_ category: ChannelCategory) -> Int {
        library.snapshot?.stations(in: category).count ?? 0
    }
}

struct CategoryStationsView: View {
    @EnvironmentObject private var library: LibraryViewModel
    let category: ChannelCategory

    var body: some View {
        let stations = library.snapshot?.stations(in: category) ?? []
        Group {
            if stations.isEmpty {
                EmptyStateView(title: "No stations", message: "Nothing in this category yet.")
            } else {
                List {
                    ForEach(stations) { station in
                        StationRow(station: station)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
