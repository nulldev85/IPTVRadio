import XCTest
@testable import IPTVRadio

/// Deterministic mock player so engine state transitions are testable.
@MainActor
final class StubAudioPlayer: AudioPlayerControlling {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEnded: (() -> Void)?

    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0

    func load(url: URL) {
        loadedURLs.append(url)
    }

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1 }

    func simulateReady() { onReady?() }
    func simulateFailure(_ message: String) { onFailure?(message) }
}

final class PlaybackEngineTests: XCTestCase {
    private func makeEngine(
        defaults: UserDefaults,
        retryLimit: Int = 2,
        timeout: Double = 15
    ) async -> (PlaybackEngine, StubAudioPlayer, ConnectivityMonitor, HistoryStore) {
        let settings = await SettingsStore(defaults: defaults)
        await MainActor.run {
            settings.retryLimit = retryLimit
            settings.streamTimeout = timeout
        }
        let player = await StubAudioPlayer()
        let connectivity = await ConnectivityMonitor()
        let history = await HistoryStore(fileStore: JSONFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("engine-test-\(UUID().uuidString)")))
        let engine = await PlaybackEngine(
            player: player,
            settings: settings,
            connectivity: connectivity,
            history: history
        )
        return (engine, player, connectivity, history)
    }

    private func station(_ id: String) -> RadioStation {
        RadioStation(
            name: "Station \(id)",
            streamURL: URL(string: "https://edge.example.net/live/\(id).m3u8")!,
            groupTitle: "Music",
            source: .xtream
        )
    }

    @MainActor
    func testPlayTransitionsToPlayingOnReady() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("a")
        engine.play(s)
        XCTAssertEqual(engine.state, .loading(s))
        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))
    }

    @MainActor
    func testFailureWithNoRetryBudgetGivesUp() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let s = station("b")
        engine.play(s)
        player.simulateFailure("connection dropped")
        XCTAssertEqual(engine.state, .failed("Could not connect to this station. Check your network or try another station.", s))
    }

    @MainActor
    func testStopStopsPlayerAndClearsNowPlaying() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("c")
        engine.play(s)
        player.simulateReady()
        engine.stop()
        XCTAssertEqual(player.stopCount, 1)
        if case .stopped(let stopped) = engine.state {
            XCTAssertEqual(stopped?.id, s.id)
        } else {
            XCTFail("Expected stopped state, got \(engine.state)")
        }
    }

    @MainActor
    func testTogglePlayPause() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("d")
        engine.play(s)
        player.simulateReady()
        engine.togglePlayPause()
        if case .paused = engine.state {} else { XCTFail("Expected paused") }
        engine.togglePlayPause()
        if case .playing = engine.state {} else { XCTFail("Expected playing") }
        XCTAssertEqual(player.pauseCount, 1)
    }

    @MainActor
    func testSleepTimerStopsPlayback() async throws {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("e")
        engine.play(s)
        player.simulateReady()
        engine.startSleepTimer(minutes: 0.02)
        XCTAssertNotNil(engine.sleepTimerDeadline)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        if case .stopped = engine.state {} else { XCTFail("Expected stopped after sleep timer") }
        XCTAssertNil(engine.sleepTimerDeadline)
    }

    @MainActor
    func testCancelSleepTimer() async {
        let (engine, _, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        engine.startSleepTimer(minutes: 30)
        XCTAssertNotNil(engine.sleepTimerDeadline)
        engine.cancelSleepTimer()
        XCTAssertNil(engine.sleepTimerDeadline)
    }

    @MainActor
    func testHistoryRecordsPlayedStation() async {
        let (engine, player, _, history) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("f")
        engine.play(s)
        player.simulateReady()
        XCTAssertEqual(history.entries.first?.station.id, s.id)
    }

    @MainActor
    func testNextPreviousNavigatesQueue() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let list = [station("g1"), station("g2"), station("g3")]
        engine.play(list[0], in: list)
        player.simulateReady()
        engine.nextStation()
        XCTAssertEqual(engine.state.station?.id, list[1].id)
        engine.previousStation()
        XCTAssertEqual(engine.state.station?.id, list[0].id)
        engine.previousStation()
        XCTAssertEqual(engine.state.station?.id, list[2].id, "Wraps to end")
    }

    @MainActor
    func testCellularBlockedWhenDisabled() async {
        let (engine, player, connectivity, _) = await makeEngine(defaults: makeIsolatedDefaults())
        await MainActor.run {
            engine.settingsForTesting.cellularAllowed = false
            connectivity.isCellular = true
        }
        let s = station("h")
        engine.play(s)
        if case .failed(let message, _) = engine.state {
            XCTAssertTrue(message.contains("Cellular"), "Got: \(message)")
        } else {
            XCTFail("Expected cellular failure, got \(engine.state)")
        }
        XCTAssertEqual(player.loadedURLs.count, 0)
    }

    @MainActor
    func testManualRetryRestartsLoad() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let s = station("i")
        engine.play(s)
        player.simulateFailure("down")
        engine.retry()
        XCTAssertEqual(engine.state, .loading(s))
        XCTAssertEqual(player.loadedURLs.count, 2)
        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))
    }
}
