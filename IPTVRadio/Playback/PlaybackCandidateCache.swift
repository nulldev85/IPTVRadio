import Foundation

/// Remembers which stream-format candidate actually played for a station, so
/// later plays skip endpoints that failed before (faster starts, fewer
/// stall-prone re-tries). Keyed by the station's primary candidate URL.
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

    func record(_ successfulURL: URL, for primaryURL: URL) {
        lock.lock()
        winners[primaryURL.absoluteString] = successfulURL.absoluteString
        let snapshot = winners
        lock.unlock()
        fileStore.save(snapshot, filename: filename)
    }
}
