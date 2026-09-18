import XCTest
@testable import IPTVRadio

/// Deterministic mock player so engine state transitions are testable.
@MainActor
final class StubAudioPlayer: AudioPlayerControlling {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEnded: (() -> Void)?
    var onDiagnostics: ((StreamDiagnosticsSample) -> Void)?
    var onMetadata: ((StreamMetadataUpdate) -> Void)?

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
        // Stop fully clears the station so the mini player goes away and the
        // user always regains the full interface.
        XCTAssertEqual(engine.state, .stopped(nil))
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

    // MARK: Stream format candidates

    @MainActor
    func testAlternativeStreamFormatTriedBeforeRetries() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let primary = URL(string: "https://edge.example.net/live/a.ts")!
        let fallback = URL(string: "https://edge.example.net/live/a.m3u8")!
        let s = RadioStation(
            name: "Multi Format",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        XCTAssertEqual(engine.state, .loading(s))
        XCTAssertEqual(player.loadedURLs, [primary])

        // The primary format fails; the next format must load immediately,
        // without consuming the retry budget.
        player.simulateFailure("ts failed")
        XCTAssertEqual(player.loadedURLs, [primary, fallback])
        XCTAssertEqual(engine.state, .loading(s))

        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))
    }

    @MainActor
    func testAllCandidatesExhaustedBeforeFailing() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let primary = URL(string: "https://edge.example.net/live/b.ts")!
        let fallback = URL(string: "https://edge.example.net/live/b.m3u8")!
        let s = RadioStation(
            name: "Both Fail",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        player.simulateFailure("ts failed")
        XCTAssertEqual(player.loadedURLs, [primary, fallback])

        // Both formats failed and there is no retry budget: surface the error.
        player.simulateFailure("hls failed too")
        if case .failed = engine.state {
            // expected
        } else {
            XCTFail("Expected failed state, got \(engine.state)")
        }
    }

    @MainActor
    func testStationWithoutAlternativesBehavesAsBefore() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let s = station("single")
        engine.play(s)
        XCTAssertEqual(player.loadedURLs, [s.streamURL])
        XCTAssertEqual(s.streamCandidates, [s.streamURL])
    }

    // MARK: Stream diagnostics

    @MainActor
    func testStreamDiagnosticsPublishedForActiveStation() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let primary = URL(string: "https://edge.example.net/live/d.ts")!
        let fallback = URL(string: "https://edge.example.net/live/d.m3u8")!
        let s = RadioStation(
            name: "Diag Station",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        player.simulateReady()
        XCTAssertNil(engine.streamDiagnostics, "Diagnostics are cleared on play")

        player.onDiagnostics?(StreamDiagnosticsSample(
            streamExtension: "ts",
            indicatedBitrate: 128_000,
            observedBitrate: 120_000,
            averageAudioBitrate: 128_000,
            audioTrackDataRate: 130_000,
            mediaRequests: 2
        ))

        let diagnostics = engine.streamDiagnostics
        XCTAssertEqual(diagnostics?.stationName, "Diag Station")
        XCTAssertEqual(diagnostics?.formatIndex, 1)
        XCTAssertEqual(diagnostics?.formatCount, 2)
        XCTAssertEqual(diagnostics?.streamType, "ts")
        XCTAssertEqual(diagnostics?.averageAudioBitrate, 128_000)
        XCTAssertEqual(diagnostics?.mediaRequests, 2)
    }

    @MainActor
    func testStopClearsStreamDiagnostics() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("diag-stop")
        engine.play(s)
        player.simulateReady()
        player.onDiagnostics?(StreamDiagnosticsSample(
            streamExtension: "m3u8",
            indicatedBitrate: 64_000,
            observedBitrate: nil,
            averageAudioBitrate: nil,
            audioTrackDataRate: nil,
            mediaRequests: 1
        ))
        XCTAssertNotNil(engine.streamDiagnostics)

        engine.stop()
        XCTAssertNil(engine.streamDiagnostics)
    }

    // MARK: Song metadata

    @MainActor
    func testSongMetadataPublishedAndCleared() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("song")
        engine.play(s)
        player.simulateReady()
        XCTAssertNil(engine.nowPlayingMetadata, "Song metadata is cleared on play")

        player.onMetadata?(StreamMetadataUpdate(
            title: "Around the World",
            artist: "Daft Punk",
            artworkData: Data([0x89, 0x50])
        ))

        XCTAssertEqual(engine.nowPlayingMetadata?.title, "Around the World")
        XCTAssertEqual(engine.nowPlayingMetadata?.artist, "Daft Punk")
        XCTAssertEqual(engine.nowPlayingMetadata?.artworkData, Data([0x89, 0x50]))

        engine.stop()
        XCTAssertNil(engine.nowPlayingMetadata)
    }

    @MainActor
    func testStationChangeClearsSongMetadata() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        engine.play(station("first"))
        player.simulateReady()
        player.onMetadata?(StreamMetadataUpdate(title: "Song A", artist: "Artist A", artworkData: nil))
        XCTAssertEqual(engine.nowPlayingMetadata?.title, "Song A")

        engine.play(station("second"))
        XCTAssertNil(engine.nowPlayingMetadata, "Switching stations clears stale song info")
    }
}
