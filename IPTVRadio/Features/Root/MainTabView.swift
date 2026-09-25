import SwiftUI

/// Main tab layout: Radio, SXM, Favorites, Search, Settings.
/// Radio only — there is no TV/video browsing anywhere in the app.
///
/// The mini player is attached to each tab's content rather than the TabView
/// itself, so it always sits *above* the tab bar and can never cover or replace
/// the navigation controls. The full player is presented once, here, rather
/// than from inside the bottom inset.
struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var settings: SettingsStore

    @State private var showNowPlaying = false
    @State private var selectedTab: AetherTab = .radio

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent { ManualRadioView() }
                .tabItem { Label("Radio", systemImage: "music.note.list") }
                .tag(AetherTab.radio)

            tabContent { RadioHomeView() }
                .tabItem { Label("SXM", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AetherTab.sxm)

            tabContent { FavoritesTabView() }
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(AetherTab.favorites)

            tabContent { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AetherTab.search)

            tabContent { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AetherTab.settings)
        }
        .tint(AetherTheme.mutedIcon)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !settings.liquidGlassEnabled {
                VStack(spacing: 0) {
                    MiniPlayerView(onOpen: { showNowPlaying = true })
                    FlatTabBar(selection: $selectedTab)
                }
            }
        }
        .background(AetherTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    /// Wraps tab content with the persistent mini player.
    @ViewBuilder
    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .toolbar(settings.liquidGlassEnabled ? .visible : .hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if settings.liquidGlassEnabled {
                    MiniPlayerView(onOpen: { showNowPlaying = true })
                }
            }
    }
}

private enum AetherTab: Int, CaseIterable, Identifiable {
    case radio, sxm, favorites, search, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .radio: "Radio"
        case .sxm: "SXM"
        case .favorites: "Favorites"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .radio: "music.note.list"
        case .sxm: "antenna.radiowaves.left.and.right"
        case .favorites: "heart"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

/// Classic full-width tab bar for listeners who turn off Liquid Glass.
private struct FlatTabBar: View {
    @Binding var selection: AetherTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AetherTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(LinearGradient(colors: [AetherTheme.coral, .cyan],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 27, height: 3)
                            .opacity(selection == tab ? 1 : 0)
                        Image(systemName: tab.symbol)
                            .font(.system(size: 23, weight: .medium))
                            .frame(height: 25)
                        Text(tab.title)
                            .font(.caption2.weight(selection == tab ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? AetherTheme.secondaryText : AetherTheme.mutedIcon)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(selection == tab ? "Selected" : "")
                .accessibilityIdentifier("tab.\(tab.title.lowercased())")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .background(AetherTheme.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            AetherTheme.border.opacity(0.5).frame(height: 1)
        }
        .accessibilityIdentifier("navigation.flatTabBar")
    }
}
