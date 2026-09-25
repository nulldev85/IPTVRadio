import XCTest
import UIKit
import MediaPlayer
@testable import IPTVRadio

/// Deterministic artwork loader: no network, no URLSession timing.
final class StubArtworkLoader: ArtworkDataLoading, @unchecked Sendable {
    enum Behavior {
        case image(Data)
        case status(Int)
        case failure
    }

    private let lock = NSLock()
    private var behaviorStorage: Behavior = .failure
    private var requests: [URL] = []

    var behavior: Behavior {
        get {
            lock.lock()
            defer { lock.unlock() }
            return behaviorStorage
        }
        set {
            lock.lock()
            behaviorStorage = newValue
            lock.unlock()
        }
    }

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(url)
        let behavior = behaviorStorage
        lock.unlock()

        switch behavior {
        case .image(let data):
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (data, response)
        case .status(let code):
            let response = HTTPURLResponse(
                url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), response)
        case .failure:
            throw URLError(.badServerResponse)
        }
    }
}

@MainActor
final class NowPlayingManagerTests: XCTestCase {
    private let artworkURL = URL(string: "https://logo.example/hits1.png")!

    private func makeStation(_ id: String, withLogo: Bool) -> RadioStation {
        RadioStation(
            name: "Station \(id)",
            streamURL: URL(string: "https://edge.example.net/live/\(id).m3u8")!,
            groupTitle: "Music",
            logoURL: withLogo ? artworkURL : nil,
            source: .xtream
        )
    }

    private func testImageData() -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.pngData() ?? Data()
    }

    func testArtworkAppliesWhenStationStillActive() async throws {
        let loader = StubArtworkLoader()
        loader.behavior = .image(testImageData())
        let manager = NowPlayingManager(artworkLoader: loader)
        defer { manager.clear() }
        let station = makeStation("a", withLogo: true)

        manager.update(state: .playing(station))
        manager.loadArtwork(for: station)

        for _ in 0..<100 where manager.lastArtworkOutcome == .none {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(manager.lastArtworkOutcome, .applied)
        XCTAssertEqual(manager.lastAppliedArtworkStationID, station.id)
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, "Station a")
    }

    func testStaleArtworkIsNotAppliedAfterStationChange() async throws {
        let loader = StubArtworkLoader()
        loader.behavior = .image(testImageData())
        let manager = NowPlayingManager(artworkLoader: loader)
        defer { manager.clear() }
        let withLogo = makeStation("a", withLogo: true)
        let withoutLogo = makeStation("b", withLogo: false)

        manager.update(state: .playing(withoutLogo))
        // Artwork for the previous station arrives after the switch.
        manager.loadArtwork(for: withLogo)

        for _ in 0..<100 where manager.lastArtworkOutcome == .none {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(manager.lastArtworkOutcome, .skippedForStaleStation)
        XCTAssertNil(manager.lastAppliedArtworkStationID)
        // Station metadata for the new station is still present.
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, "Station b")
    }

    func testStationChangeDropsPreviousArtwork() {
        let loader = StubArtworkLoader()
        let manager = NowPlayingManager(artworkLoader: loader)
        defer { manager.clear() }
        let a = makeStation("a", withLogo: true)
        let b = makeStation("b", withLogo: false)

        manager.update(state: .playing(a))
        manager.update(state: .playing(b))

        XCTAssertNil(manager.lastAppliedArtworkStationID,
                     "Switching stations must not keep the previous artwork")
        XCTAssertEqual(manager.lastArtworkOutcome, .none)
        XCTAssertEqual(manager.currentMetadata?.id, b.id)
    }

    func testStationWithoutLogoNeverRequestsArtwork() async throws {
        let loader = StubArtworkLoader()
        loader.behavior = .image(testImageData())
        let manager = NowPlayingManager(artworkLoader: loader)
        defer { manager.clear() }

        let station = makeStation("c", withLogo: false)
        manager.update(state: .playing(station))
        manager.loadArtwork(for: station)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(loader.requestedURLs.isEmpty, "No artwork request should be made without a logo URL")
        XCTAssertEqual(manager.lastArtworkOutcome, .none)
    }

    func testClearingSongRestoresStationWithoutStoppingPlayback() {
        let manager = NowPlayingManager(artworkLoader: StubArtworkLoader())
        defer { manager.clear() }
        let station = makeStation("radio", withLogo: false)
        manager.update(state: .playing(station))
        manager.applySongMetadata(
            NowPlayingMetadata(title: "Old Song", artist: "Old Artist", artworkData: nil),
            station: station
        )
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, "Old Song")
        manager.clearSongMetadata(state: .playing(station))
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, station.name)
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)
    }

    func testFailedArtworkLoadIsReportedAndNonFatal() async throws {
        let loader = StubArtworkLoader()
        loader.behavior = .status(404)
        let manager = NowPlayingManager(artworkLoader: loader)
        defer { manager.clear() }

        let station = makeStation("d", withLogo: true)
        manager.update(state: .playing(station))
        manager.loadArtwork(for: station)

        for _ in 0..<100 where manager.lastArtworkOutcome == .none {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(manager.lastArtworkOutcome, .failed)
        // Playback metadata is unaffected.
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, "Station d")
    }
}
