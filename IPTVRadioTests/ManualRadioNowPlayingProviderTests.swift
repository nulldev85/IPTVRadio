import XCTest
@testable import IPTVRadio

final class ManualRadioNowPlayingProviderTests: XCTestCase {
    func testSelectsOnlyCurrentTrack() {
        let now = Date(timeIntervalSince1970: 2_000)
        let past = ManualRadioNowPlayingProvider.Track(
            title: "Old", artist: "Artist", imagePath: nil, startTime: 1_000, endTime: 1_200
        )
        let current = ManualRadioNowPlayingProvider.Track(
            title: "Current", artist: "Singer", imagePath: nil, startTime: 1_900, endTime: 2_100
        )
        XCTAssertEqual(
            ManualRadioNowPlayingProvider.currentTrack(in: [past, current], now: now)?.title,
            "Current"
        )
        XCTAssertNil(ManualRadioNowPlayingProvider.currentTrack(in: [past], now: now))
    }

    func testParsesICYTitleWithoutPadding() {
        let block = Data("StreamTitle='Tame Impala - The Less I Know The Better  ';\0\0".utf8)
        XCTAssertEqual(
            ICYMetadataReader.title(from: block),
            "Tame Impala - The Less I Know The Better"
        )
    }
}
