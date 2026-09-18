import SwiftUI

/// Root switch: login when signed out, tabs when signed in.
struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var playback: PlaybackEngine

    var body: some View {
        Group {
            switch auth.authState {
            case .unknown:
                LaunchLoadingView()
            case .loggedOut, .expired:
                LoginView()
            case .active:
                MainTabView()
                    .task {
                        // Always refresh in the background: cached stations stay
                        // visible instantly, but a fresh fetch replaces them
                        // with current stream URLs and detection results.
                        // (UI tests inject their own data and are deterministic.)
                        if !environment.isUITestMode {
                            await library.refresh()
                            // Favorites/history saved by older app versions are
                            // migrated to the fresh station data so they play.
                            if let snapshot = library.snapshot {
                                let stations = snapshot.allRadioStations
                                environment.favorites.reconcile(with: stations)
                                environment.history.reconcile(with: stations)
                            }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.authState)
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityLabel(Text("Loading"))
    }
}
