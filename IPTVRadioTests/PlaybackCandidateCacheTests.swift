import XCTest
@testable import IPTVRadio

final class PlaybackCandidateCacheTests: XCTestCase {
    private func makeCache() -> (PlaybackCandidateCache, JSONFileStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("candidate-cache-\(UUID().uuidString)")
        let store = JSONFileStore(directory: directory)
        return (PlaybackCandidateCache(fileStore: store), store)
    }

    func testRoundTripPersistsWinner() {
        let (cache, store) = makeCache()
        let primary = URL(string: "https://host.example/live/u/p/1.m3u8")!
        let winner = URL(string: "https://host.example/live/u/p/1.ts")!

        XCTAssertNil(cache.successfulURL(for: primary))
        cache.record(winner, for: primary)
        XCTAssertEqual(cache.successfulURL(for: primary), winner.absoluteString)

        // Persisted across instances (next app launch).
        let reloaded = PlaybackCandidateCache(fileStore: store)
        XCTAssertEqual(reloaded.successfulURL(for: primary), winner.absoluteString)
    }

    func testUnknownPrimaryReturnsNil() {
        let (cache, _) = makeCache()
        XCTAssertNil(cache.successfulURL(for: URL(string: "https://host.example/unknown.m3u8")!))
    }

    func testWinnersAreKeptPerStation() {
        let (cache, _) = makeCache()
        let first = URL(string: "https://host.example/live/u/p/1.mp3")!
        let second = URL(string: "https://host.example/live/u/p/2.mp3")!
        let ts = URL(string: "https://host.example/live/u/p/1.ts")!
        let hls = URL(string: "https://host.example/live/u/p/2.m3u8")!

        cache.record(ts, for: first)
        cache.record(hls, for: second)

        XCTAssertEqual(cache.successfulURL(for: first), ts.absoluteString)
        XCTAssertEqual(cache.successfulURL(for: second), hls.absoluteString)
    }

    func testForgettingOneStationLeavesTheOthers() {
        let (cache, _) = makeCache()
        let first = URL(string: "https://host.example/live/u/p/1.mp3")!
        let second = URL(string: "https://host.example/live/u/p/2.mp3")!
        let ts = URL(string: "https://host.example/live/u/p/1.ts")!
        let hls = URL(string: "https://host.example/live/u/p/2.m3u8")!

        cache.record(ts, for: first)
        cache.record(hls, for: second)

        cache.forget(for: first)
        XCTAssertNil(cache.successfulURL(for: first))
        XCTAssertEqual(
            cache.successfulURL(for: second), hls.absoluteString,
            "Re-probing one station must not cost every other station its fast start"
        )
    }
}
