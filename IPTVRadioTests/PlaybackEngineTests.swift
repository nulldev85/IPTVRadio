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
    var onStalled: (() -> Void)?
    var onPlaybackResumed: (() -> Void)?

    private(set) var loadedURLs: [URL] = []
    /// Simulated playback progress; nil models an engine that cannot report it.
    private(set) var progressReading: Double?
    /// When set, every reading advances — an engine whose audio keeps flowing
    /// while it reports routine buffering.
    var progressAdvancesPerReading = false
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0

    func load(url: URL) {
        loadedURLs.append(url)
    }

    var playbackProgress: Double? {
        guard let value = progressReading else { return nil }
        if progressAdvancesPerReading { progressReading = value + 1 }
        return value
    }

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1 }

    func simulateReady() { onReady?() }
    func simulateFailure(_ message: String) { onFailure?(message) }
    func setProgress(_ value: Double?) { progressReading = value }
}

/// Deterministic endpoint resolver for tests (no networking).
final class StubEndpointResolver: StreamEndpointResolving, @unchecked Sendable {
    var resolvedURL: URL?

    func resolveFinalURL(for url: URL) async -> URL? {
        resolvedURL
    }
}

/// Stub out-of-stream song source for tests.
final class StubSongProvider: SongInfoProviding, @unchecked Sendable {
    var update: StreamMetadataUpdate?
    let sourceName: String

    init(sourceName: String = "stub source", update: StreamMetadataUpdate? = nil) {
        self.sourceName = sourceName
        self.update = update
    }

    func currentSong(for station: RadioStation) async -> StreamMetadataUpdate? {
        update
    }
}

final class PlaybackEngineTests: XCTestCase {
    private func makeEngine(
        defaults: UserDefaults,
        retryLimit: Int = 2,
        timeout: Double = 15,
        http: HTTPClient = URLSessionHTTPClient.providerDefault,
        audioOnlyProbe: Bool = false,
        artworkLookup: ArtworkLookupService? = nil,
        endpointResolver: StreamEndpointResolving = StubEndpointResolver(),
        songProviders: [any SongInfoProviding] = [],
        stallTimeout: TimeInterval = 12
    ) async -> (PlaybackEngine, StubAudioPlayer, ConnectivityMonitor, HistoryStore) {
        let settings = await SettingsStore(defaults: defaults)
        await MainActor.run {
            settings.retryLimit = retryLimit
            settings.streamTimeout = timeout
            // Deterministic tests: the manifest probe and online artwork
            // lookup are opt-in per test.
            settings.preferAudioOnlyRendition = audioOnlyProbe
            settings.lookupSongArtwork = false
        }
        let player = await StubAudioPlayer()
        let connectivity = await ConnectivityMonitor()
        let history = await HistoryStore(fileStore: JSONFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("engine-test-\(UUID().uuidString)")))
        let engine = await PlaybackEngine(
            player: player,
            settings: settings,
            connectivity: connectivity,
            history: history,
            http: http,
            probeCache: HLSProbeCache(fileStore: JSONFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("probe-cache-\(UUID().uuidString)"))),
            candidateCache: PlaybackCandidateCache(fileStore: JSONFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("candidate-cache-\(UUID().uuidString)"))),
            artworkLookup: artworkLookup,
            endpointResolver: endpointResolver,
            songProviders: songProviders,
            stallTimeout: stallTimeout
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
        XCTAssertNil(engine.streamDiagnostics, "Diagnostics are cleared on play")
        player.simulateReady()

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

    // MARK: Audio-only rendition preference

    @MainActor
    func testAudioOnlyRenditionPreferredWhenManifestOffersOne() async {
        let master = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",DEFAULT=YES,URI="audio/eng.m3u8",BANDWIDTH=128000
        #EXT-X-STREAM-INF:BANDWIDTH=5324800,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="aac"
        video/720p.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2",AUDIO="aac"
        audio/128k.m3u8
        """
        let http = MockHTTP.client { _ in (200, Data(master.utf8)) }
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            http: http,
            audioOnlyProbe: true
        )
        let url = URL(string: "https://cdn.example.net/live/12345.m3u8")!
        let s = RadioStation(name: "Rock Radio", streamURL: url, groupTitle: "Music Radio", source: .m3u)

        engine.play(s)

        // The probe runs before the player loads.
        for _ in 0..<50 where player.loadedURLs.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(
            player.loadedURLs.first?.absoluteString,
            "https://cdn.example.net/live/audio/128k.m3u8",
            "The dedicated audio track should be played instead of the video variant"
        )

        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))

        // Diagnostics report the audio-only rendition and its declared bandwidth.
        player.onDiagnostics?(StreamDiagnosticsSample(
            streamExtension: "m3u8",
            indicatedBitrate: nil,
            observedBitrate: 9_400_000,
            averageAudioBitrate: nil,
            audioTrackDataRate: nil,
            mediaRequests: 2
        ))
        XCTAssertEqual(engine.streamDiagnostics?.usingAudioOnlyRendition, true)
        XCTAssertEqual(engine.streamDiagnostics?.declaredAudioBandwidth, 160_000)
        XCTAssertEqual(engine.streamDiagnostics?.manifestChecked, true)
        XCTAssertEqual(engine.streamDiagnostics?.availableVariants, 2)
    }

    @MainActor
    func testSuccessfulEndpointRememberedForNextPlay() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let primary = URL(string: "https://edge.example.net/live/a.ts")!
        let fallback = URL(string: "https://edge.example.net/live/a.m3u8")!
        let s = RadioStation(
            name: "Remembered",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        XCTAssertEqual(player.loadedURLs, [primary])
        player.simulateFailure("ts dead")
        XCTAssertEqual(player.loadedURLs, [primary, fallback])
        player.simulateReady()
        engine.stop()

        // The second play starts directly at the endpoint that worked.
        engine.play(s)
        XCTAssertEqual(player.loadedURLs, [primary, fallback, fallback],
                       "Failed endpoints must be skipped on later plays")
    }

    @MainActor
    func testFormatFailureReasonIsCapturedAndScrubbed() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let primary = URL(string: "https://edge.example.net/live/user/pass/a.ts")!
        let fallback = URL(string: "https://edge.example.net/live/user/pass/a.m3u8")!
        let s = RadioStation(
            name: "Failure Reason",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        player.simulateFailure("Cannot Open https://edge.example.net/live/user/pass/a.ts (unsupported)")
        player.simulateReady()
        player.onDiagnostics?(StreamDiagnosticsSample(
            streamExtension: "m3u8",
            indicatedBitrate: nil,
            observedBitrate: nil,
            averageAudioBitrate: nil,
            audioTrackDataRate: nil,
            mediaRequests: 1
        ))

        let failure = engine.streamDiagnostics?.lastFormatFailure
        XCTAssertNotNil(failure)
        XCTAssertFalse(failure?.contains("edge.example.net") ?? true, "URLs must be scrubbed from failure reasons")
        XCTAssertTrue(failure?.contains("unsupported") ?? false, "Failure context remains visible for diagnosis")
    }

    @MainActor
    func testProbeSkippedForTSStreams() async {
        let http = MockHTTP.client { _ in
            XCTFail("The manifest probe must not fetch a raw .ts stream")
            return (200, Data())
        }
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            http: http,
            audioOnlyProbe: true
        )
        let s = RadioStation(
            name: "TS Station",
            streamURL: URL(string: "https://edge.example.net/live/user/pass/1.ts")!,
            groupTitle: "Music Radio",
            source: .xtream
        )

        engine.play(s)
        XCTAssertEqual(player.loadedURLs, [s.streamURL], ".ts candidates load directly without probing")
    }

    // MARK: Stall recovery

    @MainActor
    func testProlongedStallTriggersReconnect() async {
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            retryLimit: 1,
            stallTimeout: 0.4
        )
        let s = station("stall")
        engine.play(s)
        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))

        // Playback stalls and never resumes: the engine reconnects.
        player.onStalled?()
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        XCTAssertTrue(player.loadedURLs.count >= 2, "A stalled stream must be reloaded")
    }

    @MainActor
    func testBriefBufferingDoesNotReconnect() async {
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            retryLimit: 1,
            stallTimeout: 0.4
        )
        let s = station("brief-stall")
        engine.play(s)
        player.simulateReady()
        let loadsAfterStart = player.loadedURLs.count

        // Buffering starts and resolves quickly: no reconnect.
        player.onStalled?()
        try? await Task.sleep(nanoseconds: 100_000_000)
        player.onPlaybackResumed?()
        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(player.loadedURLs.count, loadsAfterStart, "Brief buffering must not reload the stream")
        XCTAssertEqual(engine.state, .playing(s))
    }

    @MainActor
    func testRoutineBufferingWithFlowingAudioDoesNotReconnect() async {
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            retryLimit: 1,
            stallTimeout: 0.4
        )
        let s = station("healthy-buffering")
        engine.play(s)
        player.simulateReady()
        let loadsAfterStart = player.loadedURLs.count

        // Live engines report buffering routinely as their network cache
        // refills. While playback keeps advancing the stream is healthy and
        // must be left alone: reconnecting on the report alone is what made
        // audio drop every few seconds.
        player.setProgress(0)
        player.progressAdvancesPerReading = true
        player.onStalled?()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertEqual(player.loadedURLs.count, loadsAfterStart,
                       "Buffering must not tear down a stream whose audio still flows")
        XCTAssertEqual(engine.state, .playing(s))
        XCTAssertFalse(engine.isBuffering)
    }

    @MainActor
    func testStalledAudioWithNoProgressReconnects() async {
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            retryLimit: 1,
            stallTimeout: 0.4
        )
        let s = station("frozen")
        engine.play(s)
        player.simulateReady()

        // Progress is frozen: this stall is real and must be recovered from.
        player.setProgress(9)
        player.onStalled?()
        try? await Task.sleep(nanoseconds: 1_800_000_000)

        XCTAssertTrue(player.loadedURLs.count >= 2, "A genuinely stalled stream must be reloaded")
    }

    @MainActor
    func testBufferingIsSurfacedWhileAudioIsSilent() async {
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            retryLimit: 1,
            stallTimeout: 4
        )
        let s = station("buffering-flag")
        engine.play(s)
        player.simulateReady()
        XCTAssertFalse(engine.isBuffering)

        player.setProgress(5)
        player.onStalled?()
        XCTAssertTrue(engine.isBuffering, "A silent stream must not look like it is playing")
    }

    @MainActor
    func testFailureAfterStopDoesNotResurrectTheStation() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("late-failure")
        engine.play(s)
        player.simulateReady()
        engine.stop()

        // A callback still in flight from the torn-down stream must not put a
        // failed station back on screen after an explicit stop.
        player.simulateFailure("socket closed")
        XCTAssertEqual(engine.state, .stopped(nil))
    }

    @MainActor
    func testOnlyARealTitleCountsAsStreamSuppliedSongInfo() async {
        // receivedSongInfoFromStream switches off the provider's EPG, which for
        // streams carrying no metadata is the only source of the current song.
        // Artwork alone must not set it; a real title must.
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults())
        let s = station("song-info-flag")
        engine.play(s)
        player.simulateReady()

        func refreshDiagnostics() {
            player.onDiagnostics?(StreamDiagnosticsSample(
                streamExtension: "ts",
                indicatedBitrate: nil,
                observedBitrate: nil,
                averageAudioBitrate: nil,
                audioTrackDataRate: nil,
                mediaRequests: 1
            ))
        }

        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
        player.onMetadata?(StreamMetadataUpdate(title: nil, artist: nil, artworkData: png))
        refreshDiagnostics()
        XCTAssertFalse(
            engine.streamDiagnostics?.songInfoFromStream ?? true,
            "Artwork with no title must leave the EPG as the song source"
        )

        player.onMetadata?(StreamMetadataUpdate(title: "Digital Love", artist: "Daft Punk", artworkData: nil))
        refreshDiagnostics()
        XCTAssertTrue(
            engine.streamDiagnostics?.songInfoFromStream ?? false,
            "A real title from the stream must take precedence over the EPG"
        )
    }

    @MainActor
    func testARealSongOutranksAnEarlierSourcesProgrammeInfo() async {
        // The decisive case. A panel whose EPG always names the current show
        // answers every poll, so stopping at the first non-nil answer meant the
        // broadcaster — the only source that may carry the actual track — was
        // never asked. A title with an artist is a song; a title alone is
        // programme info and must not end the search.
        let epg = StubSongProvider(
            sourceName: "provider EPG",
            update: StreamMetadataUpdate(title: "90s on 9 with a guest DJ", artist: nil, artworkData: nil)
        )
        let broadcaster = StubSongProvider(
            sourceName: "SiriusXM channel metadata",
            update: StreamMetadataUpdate(title: "Nokia", artist: "Drake", artworkData: nil)
        )
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            songProviders: [epg, broadcaster]
        )
        let s = RadioStation(
            name: "90s on 9",
            streamURL: URL(string: "https://host.example/live/u/p/77.ts")!,
            groupTitle: "Music Radio",
            source: .xtream,
            xtreamStreamID: "77"
        )

        engine.play(s)
        player.simulateReady()
        for _ in 0..<50 where engine.nowPlayingMetadata?.title == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(engine.nowPlayingMetadata?.artist, "Drake")
        XCTAssertEqual(engine.nowPlayingMetadata?.title, "Nokia")
        // No further sample is pushed here on purpose: the compatibility engine
        // emits exactly one, at startup, long before any lookup returns. The
        // source must still be current, or the row cannot answer the question
        // it exists for.
        XCTAssertEqual(
            engine.streamDiagnostics?.songInfoSource, "SiriusXM channel metadata",
            "Diagnostics must refresh when the song source changes, not stay frozen at playback start"
        )
    }

    @MainActor
    func testProgrammeInfoIsUsedWhenNoSourceHasASong() async {
        let epg = StubSongProvider(
            sourceName: "provider EPG",
            update: StreamMetadataUpdate(title: "The Heat with a guest DJ", artist: nil, artworkData: nil)
        )
        let broadcaster = StubSongProvider(sourceName: "SiriusXM channel metadata", update: nil)
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            songProviders: [epg, broadcaster]
        )
        let s = RadioStation(
            name: "The Heat",
            streamURL: URL(string: "https://host.example/live/u/p/78.ts")!,
            groupTitle: "Music Radio",
            source: .xtream,
            xtreamStreamID: "78"
        )

        engine.play(s)
        player.simulateReady()
        for _ in 0..<50 where engine.nowPlayingMetadata?.title == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(engine.nowPlayingMetadata?.title, "The Heat with a guest DJ")
        XCTAssertNil(engine.nowPlayingMetadata?.artist, "Programme info carries no artist, so no album art is attempted")
        XCTAssertEqual(engine.streamDiagnostics?.songInfoSource, "provider EPG")
    }

    // MARK: Stream-format candidates

    @MainActor
    func testDiagnosticsReportEveryCandidateOutcome() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let mp3 = URL(string: "https://edge.example.net/live/u/p/1.mp3")!
        let ts = URL(string: "https://edge.example.net/live/u/p/1.ts")!
        let hls = URL(string: "https://edge.example.net/live/u/p/1.m3u8")!
        let s = RadioStation(
            name: "Candidates",
            streamURL: mp3,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [ts, hls]
        )

        engine.play(s)
        player.simulateFailure("Cannot open the audio endpoint")
        player.simulateReady()

        let reports = engine.streamDiagnostics?.candidates ?? []
        XCTAssertEqual(reports.map(\.format), ["mp3", "ts", "m3u8"])
        if case .failed(let reason) = reports.first?.outcome {
            XCTAssertNotNil(reason, "A rejected format should carry its reason")
        } else {
            XCTFail("The audio-only candidate must be recorded as failed, got \(String(describing: reports.first?.outcome))")
        }
        XCTAssertEqual(reports[1].outcome, .playing)
        XCTAssertEqual(
            reports[2].outcome, .notTried,
            "A candidate never reached must not be reported as a failure"
        )
    }

    @MainActor
    func testRetryPreferredFormatsUnpinsARememberedEndpoint() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let mp3 = URL(string: "https://edge.example.net/live/u/p/1.mp3")!
        let ts = URL(string: "https://edge.example.net/live/u/p/1.ts")!
        let s = RadioStation(
            name: "Pinned",
            streamURL: mp3,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [ts]
        )

        engine.play(s)
        player.simulateFailure("mp3 unavailable")
        player.simulateReady()
        engine.stop()

        engine.play(s)
        XCTAssertEqual(player.loadedURLs.last, ts, "Later plays start at the remembered endpoint")

        // That memo is what can hold a station on a format carrying no song
        // metadata, so asking for the preferred formats again has to work.
        engine.retryPreferredFormats()
        XCTAssertEqual(player.loadedURLs.last, mp3, "Retrying must probe the preferred format again")
    }

    @MainActor
    func testForgetRememberedFormatStopsWithoutReplaying() async {
        // Retrying replays at once, so a connection is open again exactly when
        // the preferred endpoints are probed — and a panel that caps
        // connections refuses a second one with the same 403 it uses for a
        // format it will not serve. Stopping instead lets the next play probe
        // with nothing else open, which is the only way to tell those apart.
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let mp3 = URL(string: "https://edge.example.net/live/u/p/3.mp3")!
        let ts = URL(string: "https://edge.example.net/live/u/p/3.ts")!
        let s = RadioStation(
            name: "Clean probe",
            streamURL: mp3,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [ts]
        )

        engine.play(s)
        player.simulateFailure("mp3 unavailable")
        player.simulateReady()
        let loadsBeforeForgetting = player.loadedURLs.count

        engine.forgetRememberedFormat()
        XCTAssertEqual(engine.state, .stopped(nil), "Forgetting must stop, not replay")
        XCTAssertEqual(
            player.loadedURLs.count, loadsBeforeForgetting,
            "Nothing may be loaded: an open connection is what confuses the probe"
        )

        // The next play starts at the preferred format again.
        engine.play(s)
        XCTAssertEqual(player.loadedURLs.last, mp3)
    }

    @MainActor
    func testSkippedCandidatesAreReportedAsSkippedNotUntried() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let mp3 = URL(string: "https://edge.example.net/live/u/p/2.mp3")!
        let ts = URL(string: "https://edge.example.net/live/u/p/2.ts")!
        let s = RadioStation(
            name: "Skipping",
            streamURL: mp3,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [ts]
        )

        engine.play(s)
        player.simulateFailure("mp3 unavailable")
        player.simulateReady()
        engine.stop()

        engine.play(s)
        player.simulateReady()

        let reports = engine.streamDiagnostics?.candidates ?? []
        XCTAssertEqual(
            reports.first?.outcome, .skipped,
            "Jumped-over formats must read as skipped, not untried"
        )
        XCTAssertTrue(engine.streamDiagnostics?.startedAtRememberedEndpoint ?? false)
    }

    @MainActor
    func testQuickStreamEndSkipsToNextFormat() async {
        let (engine, player, _, _) = await makeEngine(defaults: makeIsolatedDefaults(), retryLimit: 0)
        let primary = URL(string: "https://edge.example.net/live/u/p/finite.ts")!
        let fallback = URL(string: "https://edge.example.net/live/u/p/live.m3u8")!
        let s = RadioStation(
            name: "Finite Sample",
            streamURL: primary,
            groupTitle: "Music",
            source: .xtream,
            alternativeStreamURLs: [fallback]
        )

        engine.play(s)
        player.simulateReady()
        // The endpoint ends immediately (a finite file, not a live stream).
        player.onEnded?()
        XCTAssertEqual(player.loadedURLs, [primary, fallback],
                       "A stream that ends immediately must be skipped for the next format")
    }

    @MainActor
    func testArtworkLookupEnrichesSongMetadata() async throws {
        let searchJSON = #"{"results":[{"artworkUrl100":"https://art.example/600x600bb.jpg"}]}"#
        let pngData = try XCTUnwrap(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        ))
        let http = MockHTTP.client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("itunes.apple.com") {
                return (200, Data(searchJSON.utf8))
            }
            if url.contains("art.example") {
                return (200, pngData)
            }
            return (404, Data())
        }
        let lookup = ArtworkLookupService(http: http)
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            artworkLookup: lookup
        )
        engine.settingsForTesting.lookupSongArtwork = true

        let s = station("artwork")
        engine.play(s)
        player.simulateReady()
        player.onMetadata?(StreamMetadataUpdate(title: "Around the World", artist: "Daft Punk", artworkData: nil))
        XCTAssertNil(engine.nowPlayingMetadata?.artworkImage, "Stream carries text metadata only")

        for _ in 0..<50 where engine.nowPlayingMetadata?.artworkImage == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotNil(engine.nowPlayingMetadata?.artworkImage, "Artwork should be looked up online")
    }

    // MARK: Redirected audio endpoints

    @MainActor
    func testRedirectedAudioEndpointIsResolvedBeforePlayback() async {
        let resolver = StubEndpointResolver()
        resolver.resolvedURL = URL(string: "https://cdn.example.net/final/stream.mp3")!
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            audioOnlyProbe: true,
            endpointResolver: resolver
        )
        let primary = URL(string: "https://host.example/live/u/p/1.mp3")!
        let s = RadioStation(name: "Redirected", streamURL: primary, groupTitle: "Music Radio", source: .xtream)

        engine.play(s)
        for _ in 0..<50 where player.loadedURLs.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(
            player.loadedURLs.first?.absoluteString,
            "https://cdn.example.net/final/stream.mp3",
            "The redirect-resolved audio endpoint should be played"
        )
        player.simulateReady()
        XCTAssertEqual(engine.state, .playing(s))
    }

    @MainActor
    func testUnresolvableAudioEndpointFallsBackToOriginalURL() async {
        let resolver = StubEndpointResolver()
        resolver.resolvedURL = nil
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            audioOnlyProbe: true,
            endpointResolver: resolver
        )
        let primary = URL(string: "https://host.example/live/u/p/1.aac")!
        let s = RadioStation(name: "Unresolved", streamURL: primary, groupTitle: "Music Radio", source: .xtream)

        engine.play(s)
        for _ in 0..<50 where player.loadedURLs.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(player.loadedURLs.first, primary, "Without a resolution the original endpoint is used")
    }

    // MARK: EPG song info

    @MainActor
    func testOutOfStreamSourceProvidesSongInfoWhenStreamHasNone() async {
        let provider = StubSongProvider(
            update: StreamMetadataUpdate(title: "Around the World", artist: "Daft Punk", artworkData: nil)
        )
        let (engine, player, _, _) = await makeEngine(
            defaults: makeIsolatedDefaults(),
            songProviders: [provider]
        )
        let s = RadioStation(
            name: "EPG Station",
            streamURL: URL(string: "https://host.example/live/u/p/55.m3u8")!,
            groupTitle: "Music Radio",
            source: .xtream,
            xtreamStreamID: "55"
        )

        engine.play(s)
        player.simulateReady()

        for _ in 0..<50 where engine.nowPlayingMetadata?.title == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(engine.nowPlayingMetadata?.title, "Around the World")
        XCTAssertEqual(engine.nowPlayingMetadata?.artist, "Daft Punk")

        engine.stop()
        XCTAssertNil(engine.nowPlayingMetadata)
    }
}
