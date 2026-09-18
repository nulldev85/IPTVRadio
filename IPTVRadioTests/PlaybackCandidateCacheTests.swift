import XCTest
@testable import IPTVRadio

final class PlaybackCandidateCacheTests: XCTestCase {
    func testRoundTripPersistsWinner() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("candidate-cache-\(UUID().uuidString)")
        let cache = PlaybackCandidateCache(fileStore: JSONFileStore(directory: directory))
        let primary = URL(string: "https://host.example/live/u/p/1.m3u8")!
        let winner = URL(string: "https://host.example/live/u/p/1.ts")!

        XCTAssertNil(cache.successfulURL(for: primary))
        cache.record(winner, for: primary)
        XCTAssertEqual(cache.successfulURL(for: primary), winner.absoluteString)

        // Persisted across instances (next app launch).
        let reloaded = PlaybackCandidateCache(fileStore: JSONFileStore(directory: directory))
        XCTAssertEqual(reloaded.successfulURL(for: primary), winner.absoluteString)
    }

    func testUnknownPrimaryReturnsNil() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("candidate-cache-\(UUID().uuidString)")
        let cache = PlaybackCandidateCache(fileStore: JSONFileStore(directory: directory))
        XCTAssertNil(cache.successfulURL(for: URL(string: "https://host.example/unknown.m3u8")!))
    }
}
