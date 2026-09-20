import Foundation
import VLCKitSPM

/// libVLC-backed player: the compatibility engine for streams AVPlayer cannot
/// play — raw MPEG-TS, redirecting audio-only endpoints, and other formats
/// providers serve that CFNetwork/AVPlayer refuses.
final class VLCPlayerAdapter: NSObject, AudioPlayerControlling {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEnded: (() -> Void)?
    var onDiagnostics: ((StreamDiagnosticsSample) -> Void)?
    var onMetadata: ((StreamMetadataUpdate) -> Void)?
    var onStalled: (() -> Void)?
    var onPlaybackResumed: (() -> Void)?

    private let player = VLCMediaPlayer()
    private var hasReportedReady = false
    private var hasReportedFailure = false

    override init() {
        super.init()
        player.delegate = self
        // Audio-only playback: no drawable is configured on purpose.
    }

    /// Deep-buffering engine: give it extra startup time before the engine's
    /// watchdog considers a stream failed.
    var startupGracePeriod: TimeInterval { 8 }

    func load(url: URL) {
        hasReportedReady = false
        hasReportedFailure = false
        let media = VLCMedia(url: url)
        // Live-radio tuning: a few seconds of network buffer absorbs jitter
        // without delaying startup or forcing live-edge resyncs (a buffer that
        // is too large makes VLC periodically jump back to the live edge,
        // which sounds like constant stuttering). The HTTP reconnect option
        // lets VLC recover dropped connections by itself.
        media.addOption(":network-caching=4000")
        media.addOption(":http-reconnect")
        player.media = media
        // The player protocol contract is "load prepares and starts the
        // stream" (the engine never issues a separate play on load), so VLC
        // must be told to start here — otherwise it idles and the engine's
        // watchdog eventually reports a failure.
        player.play()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
        player.media = nil
    }
}

extension VLCPlayerAdapter: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .playing:
            if !hasReportedReady {
                hasReportedReady = true
                onReady?()
            }
            onPlaybackResumed?()
        case .buffering, .opening:
            onStalled?()
        case .error:
            if !hasReportedFailure {
                hasReportedFailure = true
                onFailure?("The compatibility engine could not open this stream.")
            }
        case .ended:
            onEnded?()
        default:
            break
        }
    }
}
