import XCTest
@testable import IPTVRadio

final class M3UParserTests: XCTestCase {
    func testParsesBasicEntries() {
        let items = M3UParser.parse(Fixtures.playlistText)
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items[0].name, "SiriusXM Hits 1")
        XCTAssertEqual(items[0].groupTitle, "SiriusXM")
        XCTAssertEqual(items[0].tvgID, "sxm-hits1")
        XCTAssertEqual(items[0].logoURL?.absoluteString, "https://logo.example/hits1.png")
        XCTAssertEqual(items[0].url.absoluteString, "https://edge.example.net:8042/live/8020.m3u8")
    }

    func testHandlesCRLFAndBOM() {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,Station A\r\nhttps://example.org/a.mp3\r\n"
        let items = M3UParser.parse(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Station A")
    }

    func testAttributeValuesWithCommasAndQuotes() {
        let items = M3UParser.parse(Fixtures.playlistText)
        let smooth = try? XCTUnwrap(items.first { $0.name.contains("Smooth Jazz") })
        XCTAssertEqual(smooth?.name, "Smooth Jazz 24/7, the best mix")
        XCTAssertEqual(smooth?.groupTitle, "Music Radio")
    }

    func testEXTGRPFallback() {
        let items = M3UParser.parse(Fixtures.playlistText)
        let talk = try? XCTUnwrap(items.first { $0.name == "News Talk 101 AM" })
        XCTAssertEqual(talk?.groupTitle, "Talk Radio")
    }

    func testMalformedEntriesSkippedValidKept() {
        let items = M3UParser.parse(Fixtures.malformedPlaylistText)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Still Valid")
    }

    func testEmptyPlaylistYieldsNoItems() {
        XCTAssertEqual(M3UParser.parse(Fixtures.emptyPlaylistText).count, 0)
        XCTAssertEqual(M3UParser.parse("").count, 0)
    }

    func testEntryWithoutExtInfUsesURLFallbackName() {
        let text = "#EXTM3U\nhttps://example.org/cool_station.mp3\n"
        let items = M3UParser.parse(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "cool station")
    }

    func testVeryLargePlaylistParsesQuicklyAndCompletely() {
        let text = Fixtures.largePlaylist(entryCount: 20_000)
        let start = Date()
        let items = M3UParser.parse(text)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(items.count, 20_000)
        XCTAssertLessThan(elapsed, 10, "Large playlist parsing took too long: \(elapsed)s")
        // Verify order and a sample entry.
        XCTAssertEqual(items[19_999].name, "Test Station 19999")
        XCTAssertEqual(items[5].url.absoluteString, "https://edge.example.net:8042/live/10005.mp3")
    }

    func testURLWithQueryParamsPreserved() {
        let text = #"#EXTINF:-1,Query Station"# + "\n" + "https://example.org/stream?id=42&type=aac\n"
        let items = M3UParser.parse(text)
        XCTAssertEqual(items[0].url.query, "id=42&type=aac")
    }
}
