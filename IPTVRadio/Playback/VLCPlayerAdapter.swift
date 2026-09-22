import Foundation
import UIKit
import VLCKitSPM

/// libVLC-backed player: the compatibility engine for streams AVPlayer cannot
/// play — raw MPEG-TS, redirecting audio-only endpoints, and other formats
/// providers serve that CFNetwork/AVPlayer refuses.
///
/// All mutable state here is touched only from the main thread: VLCKit
/// dispatches its delegate callbacks onto the main queue, and the engine that
/// drives `load`/`play`/`pause`/`stop` is main-actor isolated.
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

    /// Counts libVLC's time-changed events. libVLC stops emitting them as soon
    /// as the input really stalls, so a rising count proves audio is still
    /// flowing. That is what lets the engine tell a genuine stall from the
    /// buffering notifications libVLC emits routinely while perfectly healthy.
    /// Never reset: the engine only compares successive readings.
    private var progressTicks: Double = 0

    /// When the current media was loaded. Tearing down the previous media can
    /// surface its own end/stop events a few milliseconds later; they must not
    /// be mistaken for the new stream ending.
    private var loadedAt: Date?

    private var isSettlingAfterLoad: Bool {
        guard let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < 0.35
    }

    /// Last song info handed to the engine, so the same song is not re-emitted.
    private var lastEmittedMetadata: StreamMetadataUpdate?
    /// Safety net behind libVLC's meta-changed callback (see `pollMetadata`).
    private var metadataTimer: Timer?

    override init() {
        super.init()
        player.delegate = self
        // Audio-only playback: no drawable is configured on purpose.
    }

    deinit {
        // The run loop holds the timer, not this object: without this it would
        // keep firing for the lifetime of the app.
        metadataTimer?.invalidate()
    }

    /// Deep-buffering engine: give it extra startup time before the engine's
    /// watchdog considers a stream failed.
    var startupGracePeriod: TimeInterval { 8 }

    var playbackProgress: Double? { progressTicks }

    func load(url: URL) {
        hasReportedReady = false
        hasReportedFailure = false
        lastEmittedMetadata = nil
        // libVLC requires a stopped player before its media is swapped.
        // Assigning media to a live player leaves the previous input thread
        // running, which surfaces as overlapping audio or a player that never
        // reports `playing` again. Every reload — format switch, reconnect
        // after a stall — comes through here, so the stop belongs here.
        player.stop()
        loadedAt = Date()

        let media = VLCMedia(url: url)
        // Live-radio tuning:
        //
        // - `no-video` matters more than it looks. Configuring no drawable
        //   stops VLC *displaying* video but not decoding it, and provider
        //   MPEG-TS feeds routinely carry a video track. Decoding a track
        //   nothing renders burns CPU and battery and starves the audio
        //   pipeline on a phone, especially in the background — a direct cause
        //   of dropouts. Radio never needs it.
        // - `clock-jitter=0` disables the input-clock jitter heuristic that
        //   makes VLC distrust an IPTV stream's irregular PCR timestamps and
        //   periodically resync to the live edge — audible as the constant
        //   stuttering this buffer was previously shrunk to avoid. Disabling it
        //   is what lets a real jitter buffer be used instead of a tiny one.
        //   (If stuttering ever persists, `:clock-synchro=0` is the next knob;
        //   it is left at VLC's automatic default here.)
        // - `network-caching` is the jitter buffer itself, in milliseconds.
        // - `http-reconnect` lets VLC recover a dropped connection by itself.
        media.addOption(":no-video")
        media.addOption(":clock-jitter=0")
        media.addOption(":network-caching=4000")
        media.addOption(":http-reconnect")
        // Song info: libVLC reports the stream's ICY/Shoutcast title through
        // the media's metadata, updating it whenever the song changes.
        media.delegate = self
        player.media = media
        startMetadataPolling()
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
        stopMetadataPolling()
        lastEmittedMetadata = nil
        player.stop()
        player.media = nil
        loadedAt = nil
    }
}

// MARK: - Song metadata (ICY / stream metadata)

extension VLCPlayerAdapter: VLCMediaDelegate {
    /// libVLC parsed new metadata for the stream — usually a song change.
    func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        emitMetadataIfChanged()
    }
}

fileprivate extension VLCPlayerAdapter {
    /// libVLC's meta-changed callback is the primary signal. Some inputs
    /// refresh the ICY title without emitting one, so a slow poll backs it up;
    /// emission is change-gated, so an extra read costs nothing.
    func startMetadataPolling() {
        stopMetadataPolling()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.emitMetadataIfChanged()
        }
        // .common keeps it firing while the user scrolls a list.
        RunLoop.main.add(timer, forMode: .common)
        metadataTimer = timer
    }

    func stopMetadataPolling() {
        metadataTimer?.invalidate()
        metadataTimer = nil
    }

    /// Reads the stream's current song info and forwards it when it changed.
    ///
    /// Radio streams put the song in the ICY "now playing" field, nearly always
    /// as "Artist - Title"; `title`/`artist` are only populated by streams that
    /// expose real tags. Text is enough on its own — the engine turns an
    /// artist and title into album art through its artwork lookup.
    func emitMetadataIfChanged() {
        guard let meta = player.media?.metaData else { return }
        var update = StreamMetadataUpdate(
            title: trimmed(meta.nowPlaying) ?? trimmed(meta.title),
            artist: trimmed(meta.artist) ?? trimmed(meta.albumArtist),
            artworkData: nil
        )
        update = StreamMetadataParser.splittingCombinedTitle(update)
        guard !update.isEmpty else { return }
        guard update.title != lastEmittedMetadata?.title
                || update.artist != lastEmittedMetadata?.artist else { return }
        // Embedded art is rare on live radio but free when libVLC has it.
        if let artwork = meta.artwork, let data = artwork.pngData() {
            update.artworkData = data
        }
        lastEmittedMetadata = update
        onMetadata?(update)
    }

    func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

extension VLCPlayerAdapter: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .playing:
            // A state change back to playing is also progress: it keeps the
            // stall check working even if time-changed events are sparse.
            progressTicks += 1
            if !hasReportedReady {
                hasReportedReady = true
                onReady?()
                // Show the song straight away rather than after the first poll.
                emitMetadataIfChanged()
            }
            onPlaybackResumed?()
        case .buffering, .opening:
            // Informational on a live stream: libVLC reports buffering every
            // time its cache refills. The engine treats this as a hint and
            // confirms against `playbackProgress` before reconnecting.
            onStalled?()
        case .error:
            if !hasReportedFailure {
                hasReportedFailure = true
                onFailure?("The compatibility engine could not open this stream.")
            }
        case .ended:
            // Our own stop() during a reload can arrive here moments later;
            // that is the previous media finishing, not this stream ending.
            guard !isSettlingAfterLoad else { break }
            onEnded?()
        default:
            break
        }
    }

    /// libVLC reports playback progress several times a second while audio is
    /// actually being rendered, and goes quiet the moment the input stalls.
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        progressTicks += 1
    }
}
