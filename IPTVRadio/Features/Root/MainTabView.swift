import SwiftUI

/// Main tab layout: Radio (SiriusXM-focused), Search, Library, Settings.
/// Radio only — there is no TV/video browsing anywhere in the app.
///
/// The mini player is attached to each tab's content rather than the TabView
/// itself, so it always sits *above* the tab bar and can never cover or replace
/// the navigation controls. The full player is presented once, here, rather
/// than from inside the bottom inset.
struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryViewModel

    @State private var showNowPlaying = false

    var body: some View {
        TabView {
            tabContent { RadioHomeView() }
                .tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }

            tabContent { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            tabContent { FavoritesTabView() }
                .tabItem { Label("Favorites", systemImage: "heart") }

            tabContent { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    /// Wraps tab content with the persistent mini player.
    @ViewBuilder
    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerView(onOpen: { showNowPlaying = true })
            }
    }
}
