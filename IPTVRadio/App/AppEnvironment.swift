import Foundation
import SwiftUI

/// Root application state machine for authentication.
enum AuthState: Equatable {
    case unknown
    case loggedOut
    case active(SessionInfo)
    case expired
}

/// Factory that chooses a production or UI-test environment.
enum AppEnvironmentFactory {
    @MainActor
    static func makeEnvironment(processArguments arguments: [String]) -> AppEnvironment {
        // UI tests pass launch arguments explicitly. The unit-test host also
        // runs this app; detect XCTest so tests get a deterministic
        // environment (in-memory secrets, mocked network, no real playback).
        if arguments.contains("-UITestMock") || NSClassFromString("XCTestCase") != nil {
            let scenario = UITestSupport.scenario(from: arguments)
            return AppEnvironment(
                uitestMode: true,
                uitestScenario: scenario
            )
        }
        return AppEnvironment(uitestMode: false, uitestScenario: nil)
    }
}

/// Dependency-injection container for the whole app.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let favorites: FavoritesStore
    let history: HistoryStore
    let credentials: CredentialsStore
    let connectivity: ConnectivityMonitor
    let cache: StationCache
    let httpClient: HTTPClient
    let playback: PlaybackEngine
    let library: LibraryViewModel
    let auth: AuthViewModel
    let isUITestMode: Bool

    init(
        uitestMode: Bool,
        uitestScenario: UITestScenario?
    ) {
        let settings = SettingsStore(
            defaults: uitestMode ? UserDefaults(suiteName: "uitest-settings") ?? .standard : .standard
        )
        self.settings = settings
        self.isUITestMode = uitestMode
        let fileStore = uitestMode
            ? JSONFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("uitest-store"))
            : JSONFileStore()
        favorites = FavoritesStore(fileStore: fileStore)
        history = HistoryStore(fileStore: fileStore)
        // UI tests must never touch the real Keychain.
        credentials = uitestMode
            ? CredentialsStore(secrets: MemorySecretStore())
            : CredentialsStore()
        connectivity = ConnectivityMonitor()
        cache = StationCache(fileStore: fileStore)
        httpClient = uitestMode
            ? MockHTTPClient()
            : URLSessionHTTPClient.providerDefault

        let nowPlaying = NowPlayingManager()
        playback = PlaybackEngine(
            player: uitestMode ? MockAudioPlayer() : AVAudioPlayerAdapter(),
            settings: settings,
            connectivity: connectivity,
            history: history,
            nowPlaying: nowPlaying
        )
        library = LibraryViewModel(
            libraryService: LibraryService(cache: cache),
            settings: settings,
            credentials: credentials,
            httpClient: httpClient
        )
        auth = AuthViewModel(credentials: credentials, settings: settings)

        if uitestMode, let scenario = uitestScenario {
            UITestSupport.configure(
                environment: self,
                scenario: scenario
            )
        } else {
            connectivity.start()
            library.restoreFromCache()
            auth.restoreSession()
        }
    }
}
