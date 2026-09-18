import XCTest
import AVFoundation
@testable import IPTVRadio

final class StreamMetadataParserTests: XCTestCase {
    private func id3Item(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as AnyObject
        return item
    }

    func testParsesTitleArtistAndArtwork() throws {
        let artworkData = Data([0x89, 0x50, 0x4E, 0x47])
        let items: [AVMetadataItem] = [
            id3Item(.id3MetadataTitleDescription, value: "Killing in the Name" as NSString),
            id3Item(.id3MetadataLeadPerformer, value: "Rage Against the Machine" as NSString),
            id3Item(.id3MetadataAttachedPicture, value: artworkData as NSData),
        ]

        let update = try XCTUnwrap(StreamMetadataParser.parse(items: items))
        XCTAssertEqual(update.title, "Killing in the Name")
        XCTAssertEqual(update.artist, "Rage Against the Machine")
        XCTAssertEqual(update.artworkData, artworkData)
    }

    func testSplitsArtistAndTitleWhenOnlyTitlePresent() throws {
        let items: [AVMetadataItem] = [
            id3Item(.id3MetadataTitleDescription, value: "Daft Punk - Around the World" as NSString),
        ]
        let update = try XCTUnwrap(StreamMetadataParser.parse(items: items))
        XCTAssertEqual(update.artist, "Daft Punk")
        XCTAssertEqual(update.title, "Around the World")
    }

    func testReturnsNilWhenNothingRecognized() {
        let items: [AVMetadataItem] = [
            id3Item(.id3MetadataAlbumTitle, value: "Some Album" as NSString),
        ]
        XCTAssertNil(StreamMetadataParser.parse(items: items))
    }

    func testIgnoresEmptyValues() {
        let items: [AVMetadataItem] = [
            id3Item(.id3MetadataTitleDescription, value: "" as NSString),
        ]
        XCTAssertNil(StreamMetadataParser.parse(items: items))
    }

    func testArtworkOnlyUpdateIsValid() throws {
        let artworkData = Data([0xFF, 0xD8, 0xFF])
        let items: [AVMetadataItem] = [
            id3Item(.id3MetadataAttachedPicture, value: artworkData as NSData),
        ]
        let update = try XCTUnwrap(StreamMetadataParser.parse(items: items))
        XCTAssertNil(update.title)
        XCTAssertNil(update.artist)
        XCTAssertEqual(update.artworkData, artworkData)
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
