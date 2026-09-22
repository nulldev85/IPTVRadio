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

        XCTAssertNil(cache.successfulURL(for: primary, engine: .vlc))
        cache.record(winner, for: primary, engine: .vlc)
        XCTAssertEqual(cache.successfulURL(for: primary, engine: .vlc), winner.absoluteString)

        // Persisted across instances (next app launch).
        let reloaded = PlaybackCandidateCache(fileStore: store)
        XCTAssertEqual(reloaded.successfulURL(for: primary, engine: .vlc), winner.absoluteString)
    }

    func testUnknownPrimaryReturnsNil() {
        let (cache, _) = makeCache()
        XCTAssertNil(
            cache.successfulURL(for: URL(string: "https://host.example/unknown.m3u8")!, engine: .vlc)
        )
    }

    func testWinnerIsRememberedPerEngine() {
        // The engines play different formats: AVPlayer cannot open raw MPEG-TS
        // and settles for the panel's transcoded HLS, while the compatibility
        // engine plays the original. Sharing one memo strands a listener on the
        // other engine's compromise — worse audio, with nothing to explain it.
        let (cache, _) = makeCache()
        let primary = URL(string: "https://host.example/live/u/p/1.mp3")!
        let hls = URL(string: "https://host.example/live/u/p/1.m3u8")!
        let ts = URL(string: "https://host.example/live/u/p/1.ts")!

        cache.record(hls, for: primary, engine: .avplayer)
        XCTAssertEqual(cache.successfulURL(for: primary, engine: .avplayer), hls.absoluteString)
        XCTAssertNil(
            cache.successfulURL(for: primary, engine: .vlc),
            "What played on one engine must not pin the other"
        )

        cache.record(ts, for: primary, engine: .vlc)
        XCTAssertEqual(cache.successfulURL(for: primary, engine: .vlc), ts.absoluteString)
        XCTAssertEqual(
            cache.successfulURL(for: primary, engine: .avplayer), hls.absoluteString,
            "Each engine keeps its own winner"
        )
    }

    func testForgettingOneEngineLeavesTheOther() {
        let (cache, _) = makeCache()
        let primary = URL(string: "https://host.example/live/u/p/2.mp3")!
        let hls = URL(string: "https://host.example/live/u/p/2.m3u8")!
        let ts = URL(string: "https://host.example/live/u/p/2.ts")!

        cache.record(hls, for: primary, engine: .avplayer)
        cache.record(ts, for: primary, engine: .vlc)

        cache.forget(for: primary, engine: .vlc)
        XCTAssertNil(cache.successfulURL(for: primary, engine: .vlc))
        XCTAssertEqual(cache.successfulURL(for: primary, engine: .avplayer), hls.absoluteString)
    }
}
