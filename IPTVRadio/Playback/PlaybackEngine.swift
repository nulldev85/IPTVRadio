import Foundation
import AVFoundation

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var isBuffering = false
    @Published private(set) var sleepTimerDeadline: Date?
    @Published private(set) var currentRouteDescription: String = "Device"
    /// Live stream diagnostics for the active station (visible in-app because
    /// builds are installed from CI artifacts without console access).
    @Published private(set) var streamDiagnostics: StreamDiagnostics?
    /// Current song metadata from the stream (ID3): title, artist and artwork.
    @Published private(set) var nowPlayingMetadata: NowPlayingMetadata?

    /// The list used for next/previous navigation.
    var queue: [RadioStation] = []

    /// Test-only access to playback settings.
    var settingsForTesting: SettingsStore { settings }

    private let player: AudioPlayerControlling
    private let audioSession: AudioSessionControlling
    private let settings: SettingsStore
    private let connectivity: ConnectivityMonitor
    private let history: HistoryStore
    private let nowPlaying: NowPlayingManager
    private let hlsProbe: HLSManifestProbe
    private let probeCache: HLSProbeCache
    private let candidateCache: PlaybackCandidateCache
    private let artworkLookup: ArtworkLookupService
    private let songProviders: [any SongInfoProviding]

    private var watchdogTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempts = 0
    private var sleepTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var wantsPlayback = false
    private var pendingStation: RadioStation?
    /// Stream format candidates for the current station (primary first).
    private var streamCandidates: [URL] = []
    private var candidateIndex = 0
    /// True once the current candidate has actually played successfully.
    private var candidatePlayedSuccessfully = false
    /// Async manifest probe (audio-only rendition discovery) for the current load.
    private var probeTask: Task<Void, Never>?
    private var probeResultForActiveStation: HLSProbeResult?
    private var activePlaybackURL: URL?
    /// Why the previously tried format failed (sanitized; no URLs).
    private var lastFormatFailure: String?
    /// Why *this* candidate failed. `lastFormatFailure` outlives a candidate by
    /// design (diagnostics show the last skip), so it cannot be used to label a
    /// specific one: a candidate that played and then ended would inherit the
    /// previous candidate's reason and read as refused.
    private var candidateFailureReason: String?
    /// Reconnects if playback stays buffering for too long.
    private var stallTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private let stallTimeout: TimeInterval
    /// Gap between song-lookup passes. Injectable so the polling loop's own
    /// behaviour — the per-source backoff above — is testable without waiting.
    private let songPollInterval: TimeInterval
    /// Online song-artwork lookup for streams with text-only metadata.
    private var artworkLookupTask: Task<Void, Never>?
    /// True once the stream itself provided song metadata (ID3).
    private var receivedSongInfoFromStream = false
    /// Which out-of-stream source supplied the current song, for diagnostics.
    private var songInfoSource: String?
    /// True when the current out-of-stream answer is a show name, not a track.
    private var songInfoIsProgrammeOnly = false
    /// What each song source did on the last poll. The only way, on a device
    /// with no console, to tell "nothing publishes this track" apart from "the
    /// lookup never reached anything".
    private var songSourceReports: [SongSourceReport] = []
    /// Consecutive empty answers per source for the current station.
    private var songSourceFailures: [String: Int] = [:]
    /// The last note each source gave, so a source that is no longer being
    /// asked still shows why it stopped.
    private var songSourceLastNote: [String: String] = [:]
    /// Empty answers in a row before a source is left alone for this station.
    ///
    /// A source that cannot answer for a channel generally cannot answer for it
    /// at all: on device the broadcaster's own endpoint refused every key with
    /// 403, which at four keys a poll is eight pointless requests a minute for
    /// as long as the station plays. Three strikes is enough to establish that
    /// while still tolerating a transient failure, and the station's own reset
    /// clears it — so setting a channel key and saving, which replays the
    /// station, asks every source again.
    private static let songSourceFailureLimit = 3
    /// Last sample published, so diagnostics can be rebuilt when something
    /// other than the player changes. The engine emits a sample only once, at
    /// startup, so without this every field derived from engine state stays
    /// frozen at the moment playback began.
    private var lastDiagnosticsSample: StreamDiagnosticsSample?
    /// Polls the provider's EPG for song info when the stream carries none.
    private var epgTask: Task<Void, Never>?
    /// True when the listener paused on purpose, so route changes (headphones,
    /// Bluetooth) do not restart a stream they deliberately silenced.
    private var userPaused = false
    /// What became of each stream-format candidate, keyed by its index.
    private var candidateOutcomes: [Int: StreamCandidateReport.Outcome] = [:]
    /// True when this play began at a remembered endpoint rather than the
    /// preferred one.
    private var startedAtRememberedEndpoint = false

    init(
        player: AudioPlayerControlling = VLCPlayerAdapter(),
        audioSession: AudioSessionControlling = AVAudioSessionAdapter(),
        settings: SettingsStore,
        connectivity: ConnectivityMonitor,
        history: HistoryStore,
        nowPlaying: NowPlayingManager = NowPlayingManager(),
        http: HTTPClient = URLSessionHTTPClient.providerDefault,
        probeCache: HLSProbeCache = HLSProbeCache(),
        candidateCache: PlaybackCandidateCache = PlaybackCandidateCache(),
        artworkLookup: ArtworkLookupService? = nil,
        songProviders: [any SongInfoProviding] = [],
        stallTimeout: TimeInterval = 12,
        songPollInterval: TimeInterval = 30
    ) {
        self.player = player
        self.audioSession = audioSession
        self.settings = settings
        self.connectivity = connectivity
        self.history = history
        self.nowPlaying = nowPlaying
        self.hlsProbe = HLSManifestProbe(http: http)
        self.probeCache = probeCache
        self.candidateCache = candidateCache
        self.artworkLookup = artworkLookup ?? ArtworkLookupService(http: http)
        self.songProviders = songProviders
        self.stallTimeout = stallTimeout
        self.songPollInterval = songPollInterval
        configurePlayerCallbacks()
        registerForAudioSessionNotifications()
        nowPlaying.commandDelegate = self
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        // All of them: the song lookup in particular polls on a timer, and a
        // test that builds an engine per case would otherwise leave one
        // running behind every single one.
        watchdogTask?.cancel()
        retryTask?.cancel()
        stallTask?.cancel()
        probeTask?.cancel()
        epgTask?.cancel()
        artworkLookupTask?.cancel()
    }

    // MARK: Public controls

    func play(_ station: RadioStation, in list: [RadioStation]? = nil) {
        queue = list ?? queue
        if !queue.contains(where: { $0.id == station.id }) {
            queue.append(station)
        }
        wantsPlayback = true
        userPaused = false
        retryAttempts = 0
        pendingStation = station
        streamCandidates = station.streamCandidates
        candidateIndex = 0
        candidatePlayedSuccessfully = false
        candidateOutcomes = [:]
        startedAtRememberedEndpoint = false
        streamDiagnostics = nil
        nowPlayingMetadata = nil
        probeResultForActiveStation = nil
        activePlaybackURL = nil
        lastFormatFailure = nil
        playbackStartedAt = nil
        receivedSongInfoFromStream = false
        songInfoSource = nil
        songInfoIsProgrammeOnly = false
        songSourceReports = []
        songSourceFailures = [:]
        songSourceLastNote = [:]
        cancelStallWatchdog()
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        epgTask?.cancel()
        epgTask = nil
        beginPlayback(station)
        history.record(station)
    }

    func togglePlayPause() {
        switch state {
        case .playing(let station):
            userPaused = true
            state = .paused(station)
            player.pause()
            nowPlaying.update(state: state)
        case .paused(let station):
            userPaused = false
            state = .playing(station)
            player.play()
            nowPlaying.update(state: state)
        case .stopped(let station), .failed(_, let station):
            if let station {
                play(station)
            }
        case .idle:
            break
        case .loading:
            break
        }
    }

    func stop() {
        wantsPlayback = false
        probeTask?.cancel()
        probeTask = nil
        cancelWatchdog()
        cancelRetry()
        player.stop()
        try? audioSession.deactivate()
        // Clearing the station (nil) also removes the mini player so the user
        // always regains the full UI after an explicit stop.
        state = .stopped(nil)
        nowPlaying.clear()
        isBuffering = false
        userPaused = false
        // Dropped so a callback still in flight from the torn-down stream
        // cannot resurrect the mini player with a failure the user dismissed.
        pendingStation = nil
        streamDiagnostics = nil
        nowPlayingMetadata = nil
        probeResultForActiveStation = nil
        activePlaybackURL = nil
        lastFormatFailure = nil
        playbackStartedAt = nil
        receivedSongInfoFromStream = false
        songInfoSource = nil
        songInfoIsProgrammeOnly = false
        songSourceReports = []
        songSourceFailures = [:]
        songSourceLastNote = [:]
        cancelStallWatchdog()
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        epgTask?.cancel()
        epgTask = nil
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerDeadline = nil
    }

    func retry() {
        guard let station = state.station else { return }
        play(station)
    }

    /// Forgets the remembered endpoint and stops, without replaying.
    ///
    /// `retryPreferredFormats()` replays at once, which reopens a connection to
    /// the provider at the very moment the preferred endpoints are probed. On a
    /// panel that caps concurrent connections that is itself a cause of
    /// failure, and the panel answers a refused format and a refused second
    /// connection with the same 403 — so a retry cannot tell them apart.
    ///
    /// Clearing the memo and stopping leaves the next manual play to probe from
    /// the top with nothing else open, which can.
    func forgetRememberedFormat() {
        guard let station = state.station ?? pendingStation else { return }
        if let primary = station.streamCandidates.first {
            candidateCache.forget(for: primary)
        }
        AppLogger.playback.info("Forgot the remembered format and stopped; the next play probes from the top")
        stop()
    }

    /// Forgets the remembered endpoint for this station and replays from the
    /// preferred stream format.
    ///
    /// The remembered endpoint keeps later plays fast, but it also means one
    /// early failure can hold a station on a fallback format indefinitely. On a
    /// radio app that is expensive: the audio-only endpoints tried first carry
    /// both the better audio and the only per-song metadata a stream provides,
    /// so there has to be a way to ask for them again.
    func retryPreferredFormats() {
        guard let station = state.station ?? pendingStation else { return }
        if let primary = station.streamCandidates.first {
            candidateCache.forget(for: primary)
        }
        AppLogger.playback.info("Re-probing stream formats from the preferred option")
        play(station)
    }

    func nextStation() {
        navigate(offset: 1)
    }

    func previousStation() {
        navigate(offset: -1)
    }

    // MARK: Sleep timer

    func startSleepTimer(minutes: Double) {
        sleepTimer?.invalidate()
        sleepTimerDeadline = Date().addingTimeInterval(minutes * 60)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: max(1, minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sleepTimerFired()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerDeadline = nil
    }

    private func sleepTimerFired() {
        sleepTimer = nil
        sleepTimerDeadline = nil
        stop()
    }

    // MARK: Playback internals

    private func beginPlayback(_ station: RadioStation) {
        cancelWatchdog()
        cancelRetry()
        // Before the early return below: a probe still running from the
        // previous attempt calls `load` when it finishes, and its own guard
        // (wants playback, same station) passes even when this attempt refused
        // to start — so a station blocked for being on cellular would begin
        // playing seconds later anyway.
        probeTask?.cancel()
        probeTask = nil

        if !settings.cellularAllowed && connectivity.isCellular {
            state = .failed("Cellular streaming is off. Enable it in Settings or connect to Wi-Fi.", station)
            return
        }

        state = .loading(station)
        isBuffering = true
        nowPlaying.update(state: state, buffering: true)

        do {
            try audioSession.activateForPlayback()
        } catch {
            AppLogger.playback.error("Audio session activation failed")
        }

        loadCurrentCandidate(station)
    }

    /// Loads the currently selected stream candidate (format) for the station.
    /// HLS candidates are first checked for a dedicated audio-only rendition
    /// (radio quality/data win); results are cached so this is instant after
    /// the first play of a station.
    private func loadCurrentCandidate(_ station: RadioStation) {
        // Any resolve or probe still running belongs to the candidate we are
        // leaving. Its completion calls load(), so left alive it can hand the
        // player a superseded URL seconds after a later candidate started
        // playing — tearing down a working stream mid-song. The async paths
        // below cancel it before starting their own; the fast paths return
        // without ever reaching that line, so it is cancelled here for all of
        // them.
        probeTask?.cancel()

        // Arm the watchdog before anything asynchronous. The probe and redirect
        // resolution below run on a shared session whose resource timeout is
        // far longer than its request timeout, so a provider that trickles
        // bytes could otherwise leave the app loading indefinitely. Loading is
        // always bounded from here on; `startWatchdog` replaces this one once a
        // candidate actually reaches the player.
        startWatchdog(station: station)

        // Skip endpoints that failed last time: start at the remembered winner.
        if candidateIndex == 0,
           let primary = streamCandidates.first,
           let remembered = candidateCache.successfulURL(for: primary),
           let index = streamCandidates.firstIndex(where: { $0.absoluteString == remembered }) {
            candidateIndex = index
            startedAtRememberedEndpoint = index > 0
            // Surfaced in diagnostics: otherwise the preferred formats look
            // untried rather than deliberately jumped over.
            for earlier in 0..<index where candidateOutcomes[earlier] == nil {
                candidateOutcomes[earlier] = .skipped
            }
        }

        let candidate = currentCandidateURL(for: station)

        // Fast paths: probing disabled, or a cached probe result exists.
        if !settings.preferAudioOnlyRendition {
            load(candidate: candidate, probe: nil, station: station)
            return
        }
        if let cached = probeCache.result(for: candidate) {
            load(candidate: cached.audioOnlyURL ?? candidate, probe: cached, station: station)
            return
        }
        // Only an HLS manifest can be probed for an audio-only rendition;
        // every other format goes straight to the player.
        guard candidate.pathExtension.lowercased() == "m3u8" else {
            load(candidate: candidate, probe: nil, station: station)
            return
        }

        probeTask?.cancel()
        probeTask = Task { [weak self] in
            guard let self else { return }
            let probe = await self.hlsProbe.probe(url: candidate)
            guard !Task.isCancelled,
                  self.wantsPlayback,
                  self.state.station?.id == station.id else { return }
            if let probe {
                self.probeCache.store(probe, for: candidate)
            }
            if let audioURL = probe?.audioOnlyURL {
                AppLogger.playback.info("HLS probe: using audio-only rendition (declared \(Int((probe?.declaredAudioBandwidth ?? 0) / 1000))kbps)")
                self.load(candidate: audioURL, probe: probe, station: station)
            } else {
                self.load(candidate: candidate, probe: probe, station: station)
            }
        }
    }

    private func load(candidate: URL, probe: HLSProbeResult?, station: RadioStation) {
        candidateFailureReason = nil
        probeResultForActiveStation = probe
        activePlaybackURL = candidate
        player.load(url: candidate)
        startWatchdog(station: station)
    }

    private func currentCandidateURL(for station: RadioStation) -> URL {
        guard candidateIndex < streamCandidates.count else { return station.streamURL }
        return streamCandidates[candidateIndex]
    }


    /// True while there are further formats to try after the current one.
    private var hasFurtherCandidates: Bool {
        candidateIndex + 1 < streamCandidates.count
    }

    private func startWatchdog(station: RadioStation) {
        cancelWatchdog()
        let base = max(3, settings.streamTimeout)
        // Probe alternative formats quickly; use the full timeout on the last
        // one. Deep-buffering engines (compatibility/VLC) get extra startup
        // time so healthy streams are never killed mid-connect.
        let probe = hasFurtherCandidates ? min(base, 8) : base
        let timeout = probe + player.startupGracePeriod
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.watchdogFired(station: station)
        }
    }

    private func watchdogFired(station: RadioStation) {
        guard state.isBusy, wantsPlayback else { return }
        AppLogger.playback.error("Stream timed out; trying next option")
        // Recorded so diagnostics distinguish a timeout from a refusal.
        lastFormatFailure = "Timed out waiting for the stream to start."
        candidateFailureReason = lastFormatFailure
        handleStreamProblem(station)
    }

    private func handlePlayerFailure(_ message: String) {
        // Players keep emitting callbacks for a load the engine has already
        // abandoned (an explicit stop, a station switch). Acting on those
        // corrupts the current attempt, so only a live load is listened to.
        guard hasActiveLoad, wantsPlayback,
              let station = state.station ?? pendingStation else { return }
        // Keep the reason so diagnostics can show why a format was skipped.
        lastFormatFailure = Redactor.scrubURLs(message)
        candidateFailureReason = lastFormatFailure
        handleStreamProblem(station)
    }

    /// True while a stream the engine still cares about is loaded in the player.
    private var hasActiveLoad: Bool { activePlaybackURL != nil }

    /// Called whenever the current stream candidate fails or stalls. While
    /// alternative formats remain, the next one is tried immediately;
    /// otherwise the normal backoff retry logic runs.
    private func handleStreamProblem(_ station: RadioStation) {
        cancelWatchdog()
        cancelStallWatchdog()
        // A reconnect already waiting belongs to this same failure. Left alive
        // it fires alongside the one scheduled below, so two reconnects race
        // for the player and each burns a retry from the budget.
        cancelRetry()
        // This load is being abandoned, so nothing the player still says about
        // it should be acted on. `hasActiveLoad` is the gate for exactly that,
        // and leaving the URL set holds it open: the next candidate may be a
        // probe or a redirect resolution away, and a late failure arriving in
        // that gap was being attributed to the candidate that replaced this
        // one — marking a format failed that had never been tried, and
        // advancing past it. `load` sets it again when a stream actually
        // reaches the player.
        activePlaybackURL = nil
        // A candidate that already played is not a failed format; it stalled.
        if !candidatePlayedSuccessfully {
            candidateOutcomes[candidateIndex] = .failed(candidateFailureReason)
        }
        if !candidatePlayedSuccessfully, hasFurtherCandidates {
            candidateIndex += 1
            AppLogger.playback.info("Trying alternative stream format \(self.candidateIndex + 1) of \(self.streamCandidates.count)")
            state = .loading(station)
            isBuffering = true
            nowPlaying.update(state: state, buffering: true)
            loadCurrentCandidate(station)
            return
        }
        scheduleRetry(station: station)
    }

    private func scheduleRetry(station: RadioStation) {
        cancelWatchdog()
        cancelRetry()
        // retryLimit = number of automatic retries after the initial attempt.
        let policy = RetryPolicy(maxAttempts: settings.retryLimit)
        switch policy.nextAction(afterAttempts: retryAttempts) {
        case .retryAfterDelay(let delay):
            retryAttempts += 1
            let attempt = retryAttempts
            AppLogger.playback.info("Retry attempt \(attempt) in \(delay, format: .fixed(precision: 1))s")
            state = .loading(station)
            isBuffering = true
            nowPlaying.update(state: state, buffering: true)
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.performRetry(station: station, attempt: attempt)
            }
        case .giveUp:
            isBuffering = false
            state = .failed("Could not connect to this station. Check your network or try another station.", station)
            nowPlaying.update(state: state)
        }
    }

    private func performRetry(station: RadioStation, attempt: Int) {
        guard wantsPlayback else { return }
        AppLogger.playback.info("Retrying stream (attempt \(attempt))")
        beginPlaybackInternal(station)
    }

    /// Reload without resetting retry bookkeeping.
    private func beginPlaybackInternal(_ station: RadioStation) {
        state = .loading(station)
        isBuffering = true
        loadCurrentCandidate(station)
    }

    private func configurePlayerCallbacks() {
        player.onReady = { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleReady()
                }
            } else {
                Task { @MainActor in self.handleReady() }
            }
        }
        player.onFailure = { [weak self] message in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handlePlayerFailure(message)
                }
            } else {
                Task { @MainActor in self.handlePlayerFailure(message) }
            }
        }
        player.onDiagnostics = { [weak self] sample in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleDiagnosticsSample(sample)
                }
            } else {
                Task { @MainActor in self.handleDiagnosticsSample(sample) }
            }
        }
        player.onMetadata = { [weak self] update in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleMetadataUpdate(update)
                }
            } else {
                Task { @MainActor in self.handleMetadataUpdate(update) }
            }
        }
        player.onEnded = { [weak self] in
            guard let self else { return }
            let endHandler = {
                guard let station = self.state.station, self.wantsPlayback,
                      self.hasActiveLoad else { return }
                // Live radio should never "end". If it does within a minute the
                // endpoint is not a live stream (e.g. a finite sample file):
                // skip to the next format instead of retrying it.
                let playedFor = self.playbackStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                if playedFor < 45, self.hasFurtherCandidates {
                    AppLogger.playback.info("Stream ended quickly; skipping to the next format")
                    self.candidatePlayedSuccessfully = false
                }
                self.handleStreamProblem(station)
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(endHandler)
            } else {
                Task { @MainActor in endHandler() }
            }
        }
        player.onStalled = { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self.handleStall() }
            } else {
                Task { @MainActor in self.handleStall() }
            }
        }
        player.onPlaybackResumed = { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self.handlePlaybackResumed() }
            } else {
                Task { @MainActor in self.handlePlaybackResumed() }
            }
        }
    }

    /// A buffering report arrived while playing.
    ///
    /// This deliberately does not reconnect on the report alone. Live engines
    /// emit buffering routinely as their network cache refills, and libVLC in
    /// particular does not always follow one with a fresh "playing" event — so
    /// treating the report as a stall silently tore down healthy streams every
    /// few seconds, which is what made playback feel broken. Instead the engine
    /// watches the player's own progress and reconnects only once audio has
    /// genuinely stopped flowing for the whole stall timeout.
    private func handleStall() {
        guard wantsPlayback, hasActiveLoad,
              case .playing(let station) = state, stallTask == nil else { return }
        AppLogger.playback.info("Playback is buffering")
        // In-app only. Pushing this to the lock screen would rebuild the now
        // playing info on every routine buffering report, which flips the
        // transport to paused and drops the channel artwork — several times a
        // minute on a healthy stream. The engine does not yet know whether this
        // is a real stall; that is what the monitor below decides.
        isBuffering = true
        let baseline = player.playbackProgress
        stallTask = Task { [weak self] in
            await self?.monitorStall(station: station, baseline: baseline)
        }
    }

    /// Polls until either playback demonstrably advances (the buffering report
    /// was routine) or the stall timeout passes with no progress at all.
    private func monitorStall(station: RadioStation, baseline: Double?) async {
        let step = max(0.1, min(1, stallTimeout / 4))
        var waited: TimeInterval = 0
        var reference = baseline
        while waited < stallTimeout {
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            if Task.isCancelled { return }
            guard wantsPlayback, case .playing = state,
                  state.station?.id == station.id else {
                stallTask = nil
                return
            }
            waited += step
            let current = player.playbackProgress
            if let current, let reference, current > reference {
                stallTask = nil
                markPlaybackFlowing()
                return
            }
            // First reading this engine could supply: use it as the baseline.
            if reference == nil { reference = current }
        }
        stallTask = nil
        guard wantsPlayback, case .playing = state, state.station?.id == station.id else { return }
        AppLogger.playback.error("Stream stalled too long; reconnecting")
        handleStreamProblem(station)
    }

    /// Rebuilds diagnostics from the last sample, for state the player does not
    /// report — the song source above all, which arrives seconds after the
    /// engine's only sample.
    private func refreshDiagnostics() {
        guard let sample = lastDiagnosticsSample else { return }
        handleDiagnosticsSample(sample)
    }

    /// Playback is confirmed to be flowing again: drop the buffering indicator.
    private func markPlaybackFlowing() {
        guard case .playing = state, isBuffering else { return }
        isBuffering = false
    }

    /// The player reported it resumed: stop watching and clear the indicator.
    private func handlePlaybackResumed() {
        cancelStallWatchdog()
        markPlaybackFlowing()
    }

    private func cancelStallWatchdog() {
        stallTask?.cancel()
        stallTask = nil
    }

    private func handleDiagnosticsSample(_ sample: StreamDiagnosticsSample) {
        guard let station = state.station else { return }
        lastDiagnosticsSample = sample
        let probe = probeResultForActiveStation
        let usingAudioOnly = probe?.audioOnlyURL != nil && activePlaybackURL == probe?.audioOnlyURL
        streamDiagnostics = StreamDiagnostics(
            stationName: station.name,
            formatIndex: candidateIndex + 1,
            formatCount: max(streamCandidates.count, 1),
            streamType: sample.streamExtension,
            indicatedBitrate: sample.indicatedBitrate,
            observedBitrate: sample.observedBitrate,
            averageAudioBitrate: sample.averageAudioBitrate,
            audioTrackDataRate: sample.audioTrackDataRate,
            mediaRequests: sample.mediaRequests,
            updatedAt: Date(),
            usingAudioOnlyRendition: usingAudioOnly,
            declaredAudioBandwidth: probe?.declaredAudioBandwidth,
            manifestChecked: probe != nil,
            availableVariants: probe?.variantCount,
            audioFormat: sample.audioFormat,
            lastFormatFailure: lastFormatFailure,
            songInfoFromStream: receivedSongInfoFromStream,
            songInfoSource: songInfoSource,
            songInfoIsProgrammeOnly: songInfoIsProgrammeOnly,
            songSources: songSourceReports,
            candidates: candidateReports(),
            startedAtRememberedEndpoint: startedAtRememberedEndpoint
        )
    }

    /// Every candidate for the current station and what became of it.
    private func candidateReports() -> [StreamCandidateReport] {
        streamCandidates.enumerated().map { offset, url in
            StreamCandidateReport(
                index: offset + 1,
                format: url.pathExtension.lowercased(),
                outcome: candidateOutcomes[offset] ?? .notTried
            )
        }
    }

    /// Song metadata (artist/title/artwork) arriving from the stream or EPG.
    private func handleMetadataUpdate(_ update: StreamMetadataUpdate, fromStream: Bool = true) {
        guard let station = state.station else { return }
        // Only a real title counts. This flag switches off the provider's EPG,
        // so anything less — artwork alone, or a title the adapter could not
        // vouch for — must not set it, or it silences the one source that has
        // the song for streams carrying no metadata of their own.
        if fromStream, let title = update.title, !title.isEmpty {
            receivedSongInfoFromStream = true
        }
        let metadata = NowPlayingMetadata(
            title: update.title,
            artist: update.artist,
            artworkData: update.artworkData
        )
        nowPlayingMetadata = metadata
        nowPlaying.applySongMetadata(metadata, station: station)

        // Many radio streams carry text metadata only: look the artwork up in
        // Apple's public catalog so the now playing bar shows album art.
        guard metadata.artworkData == nil,
              settings.lookupSongArtwork,
              let artist = metadata.artist, !artist.isEmpty,
              let title = metadata.title, !title.isEmpty else { return }
        artworkLookupTask?.cancel()
        artworkLookupTask = Task { [weak self] in
            guard let self else { return }
            guard let data = await self.artworkLookup.artworkData(artist: artist, title: title) else { return }
            guard !Task.isCancelled else { return }
            // Only apply if the same song is still playing.
            guard let current = self.nowPlayingMetadata,
                  current.title == title, current.artist == artist else { return }
            let enriched = NowPlayingMetadata(title: title, artist: artist, artworkData: data)
            self.nowPlayingMetadata = enriched
            if let activeStation = self.state.station {
                self.nowPlaying.applySongMetadata(enriched, station: activeStation)
            }
        }
    }

    private func handleReady() {
        cancelWatchdog()
        cancelRetry()
        cancelStallWatchdog()
        retryAttempts = 0
        isBuffering = false
        candidatePlayedSuccessfully = true
        candidateOutcomes[candidateIndex] = .playing
        playbackStartedAt = Date()
        if let station = state.station {
            // Remember which endpoint worked so the next play starts there.
            // The candidate, not `activePlaybackURL`: an HLS probe or a
            // resolved redirect plays a URL that is not in `streamCandidates`,
            // and the lookup on the next play matches against that list — so
            // recording the played URL leaves a memo that can never match, and
            // silently disables the skip, the diagnostics and the retry for
            // exactly the audio-only endpoints they exist for.
            if candidateIndex < streamCandidates.count, let primary = streamCandidates.first {
                candidateCache.record(streamCandidates[candidateIndex], for: primary)
            }
            AppLogger.playback.info("Stream ready (format \(self.candidateIndex + 1) of \(max(self.streamCandidates.count, 1)))")
            state = .playing(station)
            nowPlaying.update(state: state, buffering: false)
            nowPlaying.loadArtwork(for: station)
            startSongInfoPolling(for: station)
            // Emit a diagnostics sample immediately: libVLC exposes no access
            // log, so this is the only one there will be.
            handleDiagnosticsSample(StreamDiagnosticsSample(
                streamExtension: activePlaybackURL?.pathExtension ?? "",
                indicatedBitrate: nil,
                observedBitrate: nil,
                averageAudioBitrate: nil,
                audioTrackDataRate: nil,
                mediaRequests: nil
            ))
        }
    }

    /// Polls the out-of-stream song sources while the stream supplies none.
    ///
    /// Sources are asked in order, most authoritative first. A real track ends
    /// the pass; a show name does not, because a panel whose EPG always names
    /// the current show would otherwise be the only source ever consulted. For a
    /// panel relaying a broadcaster's audio this lookup is the only place the
    /// current track exists at all — the stream carries no title and the audio
    /// cannot be fingerprinted on device.
    private func startSongInfoPolling(for station: RadioStation) {
        epgTask?.cancel()
        guard !songProviders.isEmpty else {
            AppLogger.playback.info("No out-of-stream song source is configured")
            return
        }
        epgTask = Task { [weak self] in
            var loggedOutcome = false
            while !Task.isCancelled {
                guard let self, self.wantsPlayback, self.state.station?.id == station.id else { return }
                // A title from the stream itself outranks every other source.
                if self.receivedSongInfoFromStream { return }

                // A title *with an artist* is a track; a title alone is
                // programme information, such as a show name. The first
                // non-nil answer is therefore not good enough to stop on: a
                // panel whose EPG always names the current show would answer
                // every time and the broadcaster — the one source that may
                // have the actual song — would never be asked.
                var song: (source: String, update: StreamMetadataUpdate)?
                var programme: (source: String, update: StreamMetadataUpdate)?
                var reports: [SongSourceReport] = []
                for provider in self.songProviders {
                    let name = provider.sourceName
                    // A source that has come back empty repeatedly for this
                    // station is left alone rather than asked forever. Still
                    // reported, with the reason it gave, so it is visible that
                    // it is being skipped rather than quietly succeeding.
                    if !provider.retriesAfterEmpty &&
                        (self.songSourceFailures[name] ?? 0) >= Self.songSourceFailureLimit {
                        let reason = self.songSourceLastNote[name]
                        reports.append(
                            SongSourceReport(
                                source: name,
                                outcome: .nothing,
                                detail: reason.map { "no longer asked — \($0)" }
                                    ?? "no longer asked after \(Self.songSourceFailureLimit) empty lookups"
                            )
                        )
                        continue
                    }
                    let answer = await provider.currentSong(for: station)
                    if Task.isCancelled { return }
                    var outcome = SongSourceReport.Outcome.nothing
                    if answer.hasTitle, let update = answer.update {
                        if answer.isSong {
                            outcome = .song
                            if song == nil { song = (provider.sourceName, update) }
                        } else {
                            outcome = .programme
                            if programme == nil { programme = (provider.sourceName, update) }
                        }
                    }
                    if outcome == .nothing {
                        self.songSourceFailures[name, default: 0] += 1
                        if let note = answer.note { self.songSourceLastNote[name] = note }
                    } else {
                        // An answer clears the count: a source that works
                        // intermittently keeps being asked.
                        self.songSourceFailures[name] = 0
                    }
                    reports.append(
                        SongSourceReport(
                            source: provider.sourceName,
                            outcome: outcome,
                            detail: answer.note
                        )
                    )
                    // A track is the best any source can do, so the search
                    // stops there; the sources already asked stay in the
                    // report, so the screen still shows the whole picture.
                    if outcome == .song { break }
                }

                // Re-checked after the awaits: the stream's own title can
                // arrive while a slow source is being polled, and it wins.
                if self.receivedSongInfoFromStream { return }
                self.songSourceReports = reports
                if let best = song ?? programme {
                    self.songInfoSource = best.source
                    self.songInfoIsProgrammeOnly = song == nil
                    self.handleMetadataUpdate(best.update, fromStream: false)
                }
                // The source is deliberately *not* cleared when a pass comes
                // back empty: it describes what is on screen, and an empty pass
                // leaves the previous answer displayed — clearing it would put
                // "None answered" under a visible title. The per-source reports
                // above carry the fresh result either way.
                //
                // The refresh is unconditional because the engine publishes
                // exactly one sample, at startup, long before any lookup
                // returns. Without it every song field on the diagnostics
                // screen stays frozen at playback start, reading "None
                // answered" even when a source did answer.
                self.refreshDiagnostics()
                // Logged once per station: which source answered, or that none
                // did, is the only way to tell a silent broadcaster from a
                // lookup that is simply not reaching anything.
                if !loggedOutcome {
                    loggedOutcome = true
                    let outcome = song.map { "song from \($0.source)" }
                        ?? programme.map { "programme info only, from \($0.source)" }
                        ?? "no source answered"
                    AppLogger.playback.info("Song lookup: \(outcome, privacy: .public)")
                    for report in reports {
                        guard let detail = report.detail else { continue }
                        AppLogger.playback.info(
                            "Song source \(report.source, privacy: .public): \(detail, privacy: .public)"
                        )
                    }
                }
                try? await Task.sleep(
                    nanoseconds: UInt64(max(0.01, self.songPollInterval) * 1_000_000_000)
                )
            }
        }
    }

    private func cancelWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func navigate(offset: Int) {
        guard !queue.isEmpty, let current = state.station,
              let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + offset + queue.count) % queue.count
        play(queue[next])
    }

    // MARK: Audio session notifications

    private func registerForAudioSessionNotifications() {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }
        notificationObservers.append(interruption)

        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
        notificationObservers.append(routeChange)

        let reset = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let station = self.state.station, self.wantsPlayback else { return }
                self.play(station)
            }
        }
        notificationObservers.append(reset)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            if case let .playing(station) = state {
                state = .paused(station)
                player.pause()
                nowPlaying.update(state: state)
            }
        case .ended:
            guard let station = state.station, wantsPlayback else { return }
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                // The system deactivated our audio session for the
                // interruption. Calling play() without reactivating it renders
                // silence while the player still reports itself as playing, so
                // nothing detects the problem and the station appears to die
                // after every phone call or Siri request.
                do {
                    try audioSession.activateForPlayback()
                } catch {
                    AppLogger.playback.error("Audio session reactivation failed after interruption")
                }
                userPaused = false
                state = .playing(station)
                player.play()
                nowPlaying.update(state: state)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        currentRouteDescription = AVAudioSession.sharedInstance().currentRoute.outputs
            .first?.portName ?? "Device"

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged: pause to avoid blasting the speaker.
            if case let .playing(station) = state {
                state = .paused(station)
                player.pause()
                nowPlaying.update(state: state)
            }
        case .newDeviceAvailable:
            // Resuming on the new route (e.g. Bluetooth connected mid-play),
            // unless the listener paused on purpose.
            if case let .paused(station) = state, wantsPlayback, !userPaused {
                state = .playing(station)
                player.play()
                nowPlaying.update(state: state)
            }
        default:
            break
        }
    }
}

// MARK: - Remote command delegation

extension PlaybackEngine: NowPlayingCommandDelegate {
    func handle(command: NowPlayingCommand) {
        switch command {
        case .play:
            if case .paused = state { togglePlayPause() }
        case .pause:
            if case .playing = state { togglePlayPause() }
        case .toggle:
            togglePlayPause()
        case .stop:
            stop()
        case .next:
            nextStation()
        case .previous:
            previousStation()
        }
    }
}
