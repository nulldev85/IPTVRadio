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
    /// Per-station channel keys for the song lookup, editable by the listener.
    let songLookupKeys: SongLookupKeyStore
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

        let keyDefaults = uitestMode
            ? UserDefaults(suiteName: "uitest-songkeys") ?? .standard
            : UserDefaults.standard
        let songLookupKeys = SongLookupKeyStore(defaults: keyDefaults)
        self.songLookupKeys = songLookupKeys
        let channelKeys = ChannelKeyResolver(overrides: songLookupKeys)

        let nowPlaying = NowPlayingManager()
        let audioPlayer: AudioPlayerControlling = uitestMode ? MockAudioPlayer() : VLCPlayerAdapter()
        playback = PlaybackEngine(
            player: audioPlayer,
            settings: settings,
            connectivity: connectivity,
            history: history,
            nowPlaying: nowPlaying,
            http: httpClient,
            // Ordered most authoritative first: the panel's own EPG knows the
            // channel, and the broadcaster is consulted only when it has
            // nothing — which for SiriusXM relays is most of the time.
            songProviders: uitestMode ? [] : [
                XtreamEPGProvider(credentials: credentials, http: httpClient),
                SiriusXMNowPlayingProvider(http: httpClient, resolver: channelKeys),
                XMPlaylistNowPlayingProvider(http: httpClient, resolver: channelKeys),
            ],
            // The engine buffers deeply, so it needs a generous stall threshold
            // before the app forces a reconnect.
            stallTimeout: 25
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
