import XCTest
@testable import IPTVRadio

final class StreamMetadataParserTests: XCTestCase {
    // MARK: Shared "Artist - Title" split
    //
    // Every source funnels through here: the engine's ICY/Shoutcast stream
    // title, the provider's EPG listing and the broadcaster lookups.

    func testSplitsCombinedICYStreamTitle() {
        let split = StreamMetadataParser.splittingCombinedTitle(
            StreamMetadataUpdate(title: "Daft Punk - Digital Love", artist: nil, artworkData: nil)
        )
        XCTAssertEqual(split.artist, "Daft Punk")
        XCTAssertEqual(split.title, "Digital Love")
    }

    func testSplitKeepsAnArtistTheStreamAlreadyProvided() {
        let split = StreamMetadataParser.splittingCombinedTitle(
            StreamMetadataUpdate(title: "A - B", artist: "Real Artist", artworkData: nil)
        )
        XCTAssertEqual(split.artist, "Real Artist", "An explicit artist must win over a guess")
        XCTAssertEqual(split.title, "A - B")
    }

    func testSplitLeavesTitlesWithoutASeparatorAlone() {
        let split = StreamMetadataParser.splittingCombinedTitle(
            StreamMetadataUpdate(title: "Station Jingle", artist: nil, artworkData: nil)
        )
        XCTAssertNil(split.artist)
        XCTAssertEqual(split.title, "Station Jingle")
    }

    func testSplitIgnoresASeparatorWithAnEmptySide() {
        let split = StreamMetadataParser.splittingCombinedTitle(
            StreamMetadataUpdate(title: " - Digital Love", artist: nil, artworkData: nil)
        )
        XCTAssertNil(split.artist, "A blank artist is worse than none: artwork lookup needs a real one")
        XCTAssertEqual(split.title, " - Digital Love")
    }

    func testNowPlayingMetadataDecodesArtworkImage() {
        // Tiny valid 1x1 PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
        let metadata = NowPlayingMetadata(title: "Song", artist: "Artist", artworkData: png)
        XCTAssertNotNil(metadata.artworkImage)

        let withoutArtwork = NowPlayingMetadata(title: "Song", artist: "Artist", artworkData: nil)
        XCTAssertNil(withoutArtwork.artworkImage)
    }
}
