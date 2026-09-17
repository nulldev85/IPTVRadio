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

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
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
        let item = AVPlayerItem(url: url)
        // Prefer the audio track for radio; allows mixed-format HLS.
        item.preferredForwardBufferDuration = 4
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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
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

    private var watchdogTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempts = 0
    private var sleepTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var wantsPlayback = false
    private var pendingStation: RadioStation?

    init(
        player: AudioPlayerControlling = AVAudioPlayerAdapter(),
        audioSession: AudioSessionControlling = AVAudioSessionAdapter(),
        settings: SettingsStore,
        connectivity: ConnectivityMonitor,
        history: HistoryStore,
        nowPlaying: NowPlayingManager = NowPlayingManager()
    ) {
        self.player = player
        self.audioSession = audioSession
        self.settings = settings
        self.connectivity = connectivity
        self.history = history
        self.nowPlaying = nowPlaying
        self.redactor = Redactor(secrets: [])
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
        cancelWatchdog()
        cancelRetry()
        player.stop()
        try? audioSession.deactivate()
        state = .stopped(state.station)
        nowPlaying.clear()
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

        player.load(url: station.streamURL)
        startWatchdog(station: station)
    }

    private func startWatchdog(station: RadioStation) {
        let timeout = max(3, settings.streamTimeout)
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.watchdogFired(station: station)
        }
    }

    private func watchdogFired(station: RadioStation) {
        guard state.isBusy, wantsPlayback else { return }
        AppLogger.playback.error("Stream timed out; scheduling retry")
        scheduleRetry(station: station)
    }

    private func handlePlayerFailure(_ message: String) {
        guard let station = state.station ?? pendingStation else { return }
        if wantsPlayback {
            scheduleRetry(station: station)
        } else {
            state = .failed(redactor.redact(message), station)
        }
    }

    private func scheduleRetry(station: RadioStation) {
        cancelWatchdog()
        let policy = RetryPolicy(maxAttempts: settings.retryLimit + 1)
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
        player.load(url: station.streamURL)
        startWatchdog(station: station)
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
        player.onEnded = { [weak self] in
            guard let self else { return }
            let endHandler = {
                // Live streams should not end; treat as a dropped connection.
                if let station = self.state.station, self.wantsPlayback {
                    self.scheduleRetry(station: station)
                }
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(endHandler)
            } else {
                Task { @MainActor in endHandler() }
            }
        }
    }

    private func handleReady() {
        cancelWatchdog()
        cancelRetry()
        retryAttempts = 0
        isBuffering = false
        if let station = state.station {
            state = .playing(station)
            nowPlaying.update(state: state, buffering: false)
            nowPlaying.loadArtwork(from: station.logoURL)
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
