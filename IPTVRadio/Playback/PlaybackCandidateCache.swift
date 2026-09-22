import Foundation

/// Remembers which stream-format candidate actually played for a station, so
/// later plays skip endpoints that failed before (faster starts, fewer
/// stall-prone re-tries).
///
/// Keyed by the station's primary candidate URL *and the engine*: the two play
/// different formats, so what worked on one says nothing about the other.
/// AVPlayer cannot open raw MPEG-TS and settles for the panel's transcoded HLS,
/// while the compatibility engine plays the original — sharing one memo between
/// them silently strands a listener on the other engine's compromise.
final class PlaybackCandidateCache {
    private let fileStore: JSONFileStore
    private let filename = "playback-candidates.json"
    private let lock = NSLock()
    private var winners: [String: String]

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        self.winners = fileStore.load([String: String].self, filename: filename) ?? [:]
    }

    /// The URL (as a string) that last played successfully for this primary URL
    /// on this engine.
    func successfulURL(for primaryURL: URL, engine: PlaybackEngineKind) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return winners[Self.key(primaryURL, engine)]
    }

    private static func key(_ primaryURL: URL, _ engine: PlaybackEngineKind) -> String {
        "\(engine.rawValue)|\(primaryURL.absoluteString)"
    }

    /// Drops the remembered winner so the next play probes from the preferred
    /// candidate again.
    ///
    /// The memo makes later plays fast, but it also means a single early
    /// failure can keep a station on a fallback format for good — which for a
    /// radio app costs both the better audio of the audio-only endpoints and
    /// the song metadata only they carry. This is the way back.
    func forget(for primaryURL: URL, engine: PlaybackEngineKind) {
        lock.lock()
        winners.removeValue(forKey: Self.key(primaryURL, engine))
        let snapshot = winners
        lock.unlock()
        fileStore.save(snapshot, filename: filename)
    }

    func record(_ successfulURL: URL, for primaryURL: URL, engine: PlaybackEngineKind) {
        lock.lock()
        winners[Self.key(primaryURL, engine)] = successfulURL.absoluteString
        let snapshot = winners
        lock.unlock()
        fileStore.save(snapshot, filename: filename)
    }
}
