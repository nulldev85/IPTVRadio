import SwiftUI

/// Main tab layout: Radio (SiriusXM-focused), Browse, Search, Library, Settings.
struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        TabView {
            RadioHomeView()
                .tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }

            BrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            LibraryTabView()
                .tabItem { Label("Library", systemImage: "heart.text.square") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView()
        }
    }
}
