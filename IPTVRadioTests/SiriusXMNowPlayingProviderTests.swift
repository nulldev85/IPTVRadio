import XCTest
@testable import IPTVRadio

final class SiriusXMNowPlayingProviderTests: XCTestCase {
    // MARK: Channel slugs

    func testStripsPanelPrefixAndPunctuation() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Radio: SiriusXM FLY"),
            ["siriusxmfly", "fly"],
            "Both shapes are tried: SiriusXM's own slugs sometimes keep the brand and sometimes drop it"
        )
    }

    func testKeepsDigitsAndDropsSeparators() {
        XCTAssertEqual(SiriusXMNowPlayingProvider.candidateSlugs(for: "90s on 9"), ["90son9"])
        XCTAssertEqual(SiriusXMNowPlayingProvider.candidateSlugs(for: "Hip-Hop Nation"), ["hiphopnation"])
        XCTAssertEqual(SiriusXMNowPlayingProvider.candidateSlugs(for: "Ozzy's Boneyard"), ["ozzysboneyard"])
        XCTAssertEqual(SiriusXMNowPlayingProvider.candidateSlugs(for: "Radio: Shade 45"), ["shade45"])
    }

    func testDeduplicatesWhenStrippingChangesNothing() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "The Heat"), ["theheat"],
            "A name with no brand to strip yields one slug, not the same one twice"
        )
    }

    func testNameWithNothingUsableYieldsNoSlugs() {
        XCTAssertTrue(SiriusXMNowPlayingProvider.candidateSlugs(for: "Radio:").isEmpty)
        XCTAssertTrue(SiriusXMNowPlayingProvider.candidateSlugs(for: "   ").isEmpty)
    }

    // MARK: Response walking

    private func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    func testFindsSongInTheDocumentedNesting() {
        let payload = json("""
        {"channelMetadataResponse":{"metaData":{"currentEvent":{
          "song":{"name":"Nokia","artists":[{"name":"Drake"}],"album":{"name":"Some Album"}}
        }}}}
        """)
        let song = SiriusXMNowPlayingProvider.findSong(in: payload)
        XCTAssertEqual(song?.title, "Nokia")
        XCTAssertEqual(song?.artist, "Drake")
    }

    func testFindsSongFromFlatKeys() {
        let payload = json(#"{"currentEvent":{"songName":"Digital Love","artistName":"Daft Punk"}}"#)
        let song = SiriusXMNowPlayingProvider.findSong(in: payload)
        XCTAssertEqual(song?.title, "Digital Love")
        XCTAssertEqual(song?.artist, "Daft Punk")
    }

    func testRequiresAnArtistAlongsideTheTitle() {
        // The whole safeguard. A lone string here is as likely to be the channel
        // or the show, and both have already been mistaken for songs in this
        // app — once visibly, and once badly enough to switch off the EPG.
        let payload = json(#"{"channel":{"name":"90s on 9"},"show":{"title":"The Heat"}}"#)
        XCTAssertNil(
            SiriusXMNowPlayingProvider.findSong(in: payload),
            "A title with no artist must not be reported as a song"
        )
    }

    func testIgnoresEmptyAndWhitespaceValues() {
        let payload = json(#"{"currentEvent":{"songName":"   ","artistName":"Drake"}}"#)
        XCTAssertNil(SiriusXMNowPlayingProvider.findSong(in: payload))
    }

    func testWalksArraysToReachTheEvent() {
        let payload = json("""
        {"events":[
          {"channel":"90s on 9"},
          {"song":{"title":"Nokia","artist":"Drake"}}
        ]}
        """)
        XCTAssertEqual(SiriusXMNowPlayingProvider.findSong(in: payload)?.artist, "Drake")
    }

    func testUnrecognisedShapeYieldsNothingRatherThanAGuess() {
        XCTAssertNil(SiriusXMNowPlayingProvider.findSong(in: json(#"{"status":"ok","code":200}"#)))
        XCTAssertNil(SiriusXMNowPlayingProvider.findSong(in: json("[]")))
    }
}
