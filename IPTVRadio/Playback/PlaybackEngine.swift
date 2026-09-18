import Foundation
import AVFoundation
import MediaPlayer

// MARK: - Playback state model

enum PlaybackState: Equatable {
    case idle
    case loading(RadioStation)
    case playing(RadioStation)
    case paused(RadioStation)
    case stopped(RadioStation?)
    case failed(String, RadioStation?)

    var station: RadioStation? {
        switch self {
        case .idle: return nil
        case .loading(let s): return s
        case .playing(let s): return s
        case .paused(let s): return s
        case .stopped(let s): return s
        case .failed(_, let s): return s
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isBusy: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Player abstraction (DI seam for tests)

protocol AudioPlayerControlling: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onEnded: (() -> Void)? { get set }
    var onDiagnostics: ((StreamDiagnosticsSample) -> Void)? { get set }
    var onMetadata: ((StreamMetadataUpdate) -> Void)? { get set }
    func load(url: URL)
    func play()
    func pause()
    func stop()
}

/// AVPlayer-backed audio player for live HTTP/HLS radio streams.
final class AVAudioPlayerAdapter: NSObject, AudioPlayerControlling {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEnded: (() -> Void)?
    var onDiagnostics: ((StreamDiagnosticsSample) -> Void)?
    var onMetadata: ((StreamMetadataUpdate) -> Void)?

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var diagnosticsTask: Task<Void, Never>?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var lastMetadata: StreamMetadataUpdate?
    private var hasReportedReady = false

    var underlyingPlayer: AVPlayer { player }

    override init() {
        super.init()
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            if player.timeControlStatus == .playing, !self.hasReportedReady {
                self.hasReportedReady = true
                self.onReady?()
            }
        }
    }

    deinit {
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func load(url: URL) {
        stopObserversForReload()
        hasReportedReady = false
        lastMetadata = nil
        let item = AVPlayerItem(url: url)
        // The provider URL is handed to AVPlayer unchanged: no transcoding,
        // recompression or rendition caps. AVPlayer picks the highest
        // sustainable audio rendition the provider offers.
        scheduleDiagnostics(for: url, item: item)
        // Stream song metadata (ID3): powers the current-song artwork in the
        // now playing bar and the lock screen.
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        metadataOutput = output
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                self?.player.play()
            case .failed:
                let message = item.error?.localizedDescription ?? "Stream could not be opened."
                self?.onFailure?(message)
            default:
                break
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onEnded?()
        }
        player.replaceCurrentItem(with: item)
    }

    /// Collects safe, non-secret stream diagnostics (type + bitrates) and
    /// publishes them after a few seconds, refreshing periodically while the
    /// item is current. SECURITY: the URL is never used; only its extension.
    private func scheduleDiagnostics(for url: URL, item: AVPlayerItem) {
        let streamExtension = url.pathExtension
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [weak self] in
            // Give AVPlayer a few seconds to gather access-log data.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            var didLog = false
            while !Task.isCancelled {
                guard let self, self.player.currentItem === item, item.error == nil else { return }
                let sample = PlaybackDiagnostics.makeSample(
                    streamExtension: streamExtension,
                    events: (item.accessLog()?.events ?? []).map { event in
                        PlaybackDiagnostics.EventSample(
                            indicatedBitrate: event.indicatedBitrate,
                            observedBitrate: event.observedBitrate,
                            averageAudioBitrate: event.averageAudioBitrate,
                            numberOfMediaRequests: event.numberOfMediaRequests
                        )
                    },
                    tracks: item.asset.tracks.map { track in
                        PlaybackDiagnostics.TrackSample(
                            mediaType: track.mediaType.rawValue,
                            estimatedDataRate: Double(track.estimatedDataRate)
                        )
                    }
                )
                if !didLog {
                    AppLogger.playback.info("Stream diagnostics (redacted): \(PlaybackDiagnostics.summary(for: sample), privacy: .public)")
                    didLog = true
                }
                self.onDiagnostics?(sample)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        stopObserversForReload()
    }

    private func stopObserversForReload() {
        statusObservation?.invalidate()
        statusObservation = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        metadataOutput = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

// MARK: - Stream song metadata (ID3)

extension AVAudioPlayerAdapter: AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let items = groups.flatMap { $0.items }
        guard let update = StreamMetadataParser.parse(items: items) else { return }
        guard update != lastMetadata else { return }
        lastMetadata = update
        onMetadata?(update)
    }
}

// MARK: - Audio session abstraction

protocol AudioSessionControlling: AnyObject {
    func activateForPlayback() throws
    func deactivate() throws
}

final class AVAudioSessionAdapter: AudioSessionControlling {
    func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true, options: [])
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Retry policy (pure logic, unit tested)

struct RetryPolicy: Equatable {
    let maxAttempts: Int
    /// Backoff bases in seconds: 1s, 2s, 4s...
    static func backoff(forAttempt attempt: Int) -> TimeInterval {
        pow(2, Double(max(0, attempt - 1)))
    }

    func nextAction(afterAttempts attempts: Int) -> RetryDecision {
        if attempts < maxAttempts {
            return .retryAfterDelay(Self.backoff(forAttempt: attempts + 1))
        }
        return .giveUp
    }
}

enum RetryDecision: Equatable {
    case retryAfterDelay(TimeInterval)
    case giveUp
}

// MARK: - Playback engine

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
    private let redactor: Redactor
    private let hlsProbe: HLSManifestProbe
    private let probeCache: HLSProbeCache

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
    private var resolveTask: Task<Void, Never>?
    private var probeResultForActiveStation: HLSProbeResult?
    private var activePlaybackURL: URL?

    init(
        player: AudioPlayerControlling = AVAudioPlayerAdapter(),
        audioSession: AudioSessionControlling = AVAudioSessionAdapter(),
        settings: SettingsStore,
        connectivity: ConnectivityMonitor,
        history: HistoryStore,
        nowPlaying: NowPlayingManager = NowPlayingManager(),
        http: HTTPClient = URLSessionHTTPClient.providerDefault,
        probeCache: HLSProbeCache = HLSProbeCache()
    ) {
        self.player = player
        self.audioSession = audioSession
        self.settings = settings
        self.connectivity = connectivity
        self.history = history
        self.nowPlaying = nowPlaying
        self.redactor = Redactor(secrets: [])
        self.hlsProbe = HLSManifestProbe(http: http)
        self.probeCache = probeCache
        configurePlayerCallbacks()
        registerForAudioSessionNotifications()
        nowPlaying.commandDelegate = self
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        watchdogTask?.cancel()
        retryTask?.cancel()
    }

    // MARK: Public controls

    func play(_ station: RadioStation, in list: [RadioStation]? = nil) {
        queue = list ?? queue
        if !queue.contains(where: { $0.id == station.id }) {
            queue.append(station)
        }
        wantsPlayback = true
        retryAttempts = 0
        pendingStation = station
        streamCandidates = station.streamCandidates
        candidateIndex = 0
        candidatePlayedSuccessfully = false
        streamDiagnostics = nil
        nowPlayingMetadata = nil
        probeResultForActiveStation = nil
        activePlaybackURL = nil
        beginPlayback(station)
        history.record(station)
    }

    func togglePlayPause() {
        switch state {
        case .playing(let station):
            state = .paused(station)
            player.pause()
            nowPlaying.update(state: state)
        case .paused(let station):
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
        resolveTask?.cancel()
        resolveTask = nil
        cancelWatchdog()
        cancelRetry()
        player.stop()
        try? audioSession.deactivate()
        // Clearing the station (nil) also removes the mini player so the user
        // always regains the full UI after an explicit stop.
        state = .stopped(nil)
        nowPlaying.clear()
        streamDiagnostics = nil
        nowPlayingMetadata = nil
        probeResultForActiveStation = nil
        activePlaybackURL = nil
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerDeadline = nil
    }

    func retry() {
        guard let station = state.station else { return }
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
        // .ts and other non-manifest candidates have nothing to probe.
        guard candidate.pathExtension.lowercased() == "m3u8" else {
            load(candidate: candidate, probe: nil, station: station)
            return
        }

        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
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
        let base = max(3, settings.streamTimeout)
        // Probe alternative formats quickly; use the full timeout on the last one.
        let timeout = hasFurtherCandidates ? min(base, 8) : base
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.watchdogFired(station: station)
        }
    }

    private func watchdogFired(station: RadioStation) {
        guard state.isBusy, wantsPlayback else { return }
        AppLogger.playback.error("Stream timed out; trying next option")
        handleStreamProblem(station)
    }

    private func handlePlayerFailure(_ message: String) {
        guard let station = state.station ?? pendingStation else { return }
        if wantsPlayback {
            handleStreamProblem(station)
        } else {
            state = .failed(redactor.redact(message), station)
        }
    }

    /// Called whenever the current stream candidate fails or stalls. While
    /// alternative formats remain, the next one is tried immediately;
    /// otherwise the normal backoff retry logic runs.
    private func handleStreamProblem(_ station: RadioStation) {
        cancelWatchdog()
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
        // retryLimit = number of automatic retries after the initial attempt.
        let policy = RetryPolicy(maxAttempts: settings.retryLimit)
        switch policy.nextAction(afterAttempts: retryAttempts) {
        case .retryAfterDelay(let delay):
            retryAttempts += 1
            let attempt = retryAttempts
            AppLogger.playback.info("Retry attempt \(attempt) in \(delay, format: .fixed(precision: 1))s")
            state = .loading(station)
            isBuffering = true
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
                // Live streams should not end; treat as a dropped connection.
                if let station = self.state.station, self.wantsPlayback {
                    self.handleStreamProblem(station)
                }
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(endHandler)
            } else {
                Task { @MainActor in endHandler() }
            }
        }
    }

    private func handleDiagnosticsSample(_ sample: StreamDiagnosticsSample) {
        guard let station = state.station else { return }
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
            manifestChecked: probe != nil
        )
    }

    /// Song metadata (artist/title/artwork) arriving from the stream.
    private func handleMetadataUpdate(_ update: StreamMetadataUpdate) {
        guard let station = state.station else { return }
        let metadata = NowPlayingMetadata(
            title: update.title,
            artist: update.artist,
            artworkData: update.artworkData
        )
        nowPlayingMetadata = metadata
        nowPlaying.applySongMetadata(metadata, station: station)
    }

    private func handleReady() {
        cancelWatchdog()
        cancelRetry()
        retryAttempts = 0
        isBuffering = false
        candidatePlayedSuccessfully = true
        if let station = state.station {
            AppLogger.playback.info("Stream ready (format \(self.candidateIndex + 1) of \(max(self.streamCandidates.count, 1)))")
            state = .playing(station)
            nowPlaying.update(state: state, buffering: false)
            nowPlaying.loadArtwork(for: station)
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
            // Resuming on the new route (e.g. Bluetooth connected mid-play).
            if case let .paused(station) = state, wantsPlayback {
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
