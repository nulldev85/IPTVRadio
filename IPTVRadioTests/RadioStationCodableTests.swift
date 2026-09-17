import XCTest
@testable import IPTVRadio

/// RadioStation is persisted to the on-disk library cache. `usesDirectSource`
/// was added after the cache format shipped, so it must decode from JSON
/// that never had the key (an older cached snapshot) without throwing.
final class RadioStationCodableTests: XCTestCase {
    func testDecodesLegacyJSONMissingUsesDirectSource() throws {
        let json = """
        {
            "id": "abc123",
            "name": "Legacy Station",
            "streamURL": "https://edge.example.net/live/1.m3u8",
            "groupTitle": "Music",
            "source": "xtream"
        }
        """
        let decoder = JSONDecoder()
        let station = try decoder.decode(RadioStation.self, from: Data(json.utf8))
        XCTAssertEqual(station.name, "Legacy Station")
        XCTAssertNil(station.usesDirectSource)
    }

    func testRoundTripsUsesDirectSource() throws {
        let station = RadioStation(
            name: "Direct",
            streamURL: URL(string: "https://edge.example.net/direct/a.mp3")!,
            source: .xtream,
            usesDirectSource: true
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(station)
        let decoded = try decoder.decode(RadioStation.self, from: data)
        XCTAssertEqual(decoded.usesDirectSource, true)
        XCTAssertEqual(decoded.id, station.id)
    }
}
