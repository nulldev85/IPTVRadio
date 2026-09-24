import Foundation

/// The engine's view of an audio player, and the dependency-injection seam
/// the tests drive instead of a real stream.
///
/// Everything the engine needs to know about playback arrives through these
/// callbacks, which is what lets the whole state machine — candidate
/// fallback, stall confirmation, reconnect backoff — be exercised without a
/// network or a device.
protocol AudioPlayerControlling: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onEnded: (() -> Void)? { get set }
    var onDiagnostics: ((StreamDiagnosticsSample) -> Void)? { get set }
    var onMetadata: ((StreamMetadataUpdate) -> Void)? { get set }
    /// Playback is waiting for data (buffering).
    var onStalled: (() -> Void)? { get set }
    /// Playback (re)started after buffering.
    var onPlaybackResumed: (() -> Void)? { get set }
    /// Extra time this engine needs before the stream can be considered
    /// failed to start (deep-buffering engines need more than the default).
    var startupGracePeriod: TimeInterval { get }
    /// An increasing measure of real playback progress, or nil when this engine
    /// cannot report one. Only successive readings are compared, so the unit
    /// does not matter. It exists so the engine can confirm a stall by seeing
    /// that audio actually stopped flowing, rather than trusting a single
    /// buffering notification — live engines emit those routinely while
    /// perfectly healthy, and acting on one tears down a working stream.
    var playbackProgress: Double? { get }
    func load(url: URL)
    func play()
    func pause()
    func stop()
}

extension AudioPlayerControlling {
    var startupGracePeriod: TimeInterval { 0 }
    var playbackProgress: Double? { nil }
}
