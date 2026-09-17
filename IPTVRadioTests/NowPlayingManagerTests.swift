import XCTest
import UIKit
import MediaPlayer
@testable import IPTVRadio

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

    private func makeManager() -> NowPlayingManager {
        MockURLProtocol.requestHandler = { request in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.systemRed.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            return (200, image.pngData() ?? Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return NowPlayingManager(artworkSession: URLSession(configuration: config))
    }

    func testArtworkAppliesWhenStationStillActive() async throws {
        let manager = makeManager()
        defer { manager.clear() }
        let station = makeStation("a", withLogo: true)

        manager.update(state: .playing(station))
        manager.loadArtwork(for: station)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let info = manager.nowPlayingInfoForTesting
        XCTAssertNotNil(info?[MPMediaItemPropertyArtwork], "Artwork should be applied for the active station")
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Station a")
    }

    func testStaleArtworkIsNotAppliedAfterStationChange() async throws {
        let manager = makeManager()
        defer { manager.clear() }
        let withLogo = makeStation("a", withLogo: true)
        let withoutLogo = makeStation("b", withLogo: false)

        manager.update(state: .playing(withoutLogo))
        // Artwork for the previous station arrives after the switch.
        manager.loadArtwork(for: withLogo)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertNil(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyArtwork],
                     "Stale artwork must not be applied to a different station")
        // Station metadata for the new station is still present.
        XCTAssertEqual(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyTitle] as? String, "Station b")
    }

    func testStationChangeDropsPreviousArtwork() {
        let manager = makeManager()
        defer { manager.clear() }
        let a = makeStation("a", withLogo: true)
        let b = makeStation("b", withLogo: false)

        manager.update(state: .playing(a))
        manager.update(state: .playing(b))

        XCTAssertNil(manager.nowPlayingInfoForTesting?[MPMediaItemPropertyArtwork],
                     "Switching stations must not keep the previous artwork")
        XCTAssertEqual(manager.currentMetadata?.id, b.id)
    }

    func testStationWithoutLogoNeverRequestsArtwork() async throws {
        var requestCount = 0
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (200, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let manager = NowPlayingManager(artworkSession: URLSession(configuration: config))
        defer { manager.clear() }

        let station = makeStation("c", withLogo: false)
        manager.update(state: .playing(station))
        manager.loadArtwork(for: station)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(requestCount, 0, "No artwork request should be made without a logo URL")
    }
}
