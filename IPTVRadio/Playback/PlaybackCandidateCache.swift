import Foundation

/// Remembers which stream-format candidate actually played for a station, so
/// later plays skip endpoints that failed before (faster starts, fewer
/// stall-prone re-tries).
///
/// Keyed by the station's primary candidate URL. It used to be keyed by engine
/// as well, because AVPlayer could not open raw MPEG-TS and settled for the
/// panel's transcoded HLS while the compatibility engine played the original —
/// one memo shared between them stranded a listener on the other's compromise.
/// There is only one engine now, so the dimension is gone; memos written by the
/// old keying no longer match, which costs one re-probe per station and nothing
/// else.
final class PlaybackCandidateCache {
    private let fileStore: JSONFileStore
    private let filename = "playback-candidates.json"
    private let lock = NSLock()
    private var winners: [String: String]

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        self.winners = fileStore.load([String: String].self, filename: filename) ?? [:]
    }

    /// The URL (as a string) that last played successfully for this primary URL.
    func successfulURL(for primaryURL: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return winners[primaryURL.absoluteString]
    }

    /// Drops the remembered winner so the next play probes from the preferred
    /// candidate again.
    ///
    /// The memo makes later plays fast, but it also means a single early
    /// failure can keep a station on a fallback format for good — which for a
    /// radio app costs both the better audio of the audio-only endpoints and
    /// the song metadata only they carry. This is the way back.
    func forget(for primaryURL: URL) {
        lock.lock()
        winners.removeValue(forKey: primaryURL.absoluteString)
        let snapshot = winners
        lock.unlock()
        fileStore.save(snapshot, filename: filename)
    }

    func record(_ successfulURL: URL, for primaryURL: URL) {
        lock.lock()
        winners[primaryURL.absoluteString] = successfulURL.absoluteString
        let snapshot = winners
        lock.unlock()
        fileStore.save(snapshot, filename: filename)
    }
}
