import XCTest
@testable import IPTVRadio

final class PlaylistStreamFormatsTests: XCTestCase {
    func testDerivesSiblingFormatForXtreamPattern() {
        let url = URL(string: "http://host.example:8080/live/user/pass/12345.m3u8?token=abc")!
        let automatic = PlaylistStreamFormats.candidates(for: url, preference: .automatic)
        XCTAssertEqual(automatic.count, 2)
        XCTAssertEqual(automatic[0].pathExtension, "ts", "Automatic prefers the original MPEG-TS format")
        XCTAssertEqual(automatic[1].pathExtension, "m3u8")
        XCTAssertEqual(automatic[0].query, "token=abc", "Signed query parameters must be preserved")

        let hlsFirst = PlaylistStreamFormats.candidates(for: url, preference: .hlsFirst)
        XCTAssertEqual(hlsFirst[0].pathExtension, "m3u8")
        XCTAssertEqual(hlsFirst[1].pathExtension, "ts")
    }

    func testTSPlaylistURLStaysPrimaryInAutomaticMode() {
        let url = URL(string: "https://host.example:8080/live/user/pass/12345.ts")!
        let automatic = PlaylistStreamFormats.candidates(for: url, preference: .automatic)
        XCTAssertEqual(automatic[0].absoluteString, url.absoluteString)
        XCTAssertEqual(automatic[1].pathExtension, "m3u8")
    }

    func testNonXtreamURLsAreLeftUntouched() {
        let cdn = URL(string: "https://cdn.example.net/rock/index.m3u8")!
        XCTAssertEqual(PlaylistStreamFormats.candidates(for: cdn, preference: .automatic), [cdn])

        let mp3 = URL(string: "https://host.example:8000/live/user/pass/1.mp3")!
        XCTAssertEqual(PlaylistStreamFormats.candidates(for: mp3, preference: .automatic), [mp3])

        let radioStream = URL(string: "https://ice.example.net/stream")!
        XCTAssertEqual(PlaylistStreamFormats.candidates(for: radioStream, preference: .automatic), [radioStream])
    }

    @MainActor
    func testM3UImportAppliesFormatPreference() async {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title="Music Radio",Rock The Bells Radio
        http://host.example:8080/live/user/pass/12345.m3u8?token=abc
        """
        MockURLProtocol.requestHandler = { _ in (200, Data(playlist.utf8)) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let http = URLSessionHTTPClient(session: URLSession(configuration: config))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("m3u-format-\(UUID().uuidString)")
        let service = LibraryService(cache: StationCache(fileStore: JSONFileStore(directory: temp)))

        let result = await service.refresh(
            credentials: M3UPlaylistCredentials(url: URL(string: "https://playlist.example/list.m3u")!),
            http: http,
            rules: .default,
            formatPreference: .automatic
        )
        guard case .success(let snapshot) = result, let station = snapshot.allRadioStations.first else {
            return XCTFail("Expected a station from the playlist, got \(result)")
        }
        XCTAssertEqual(station.streamCandidates.count, 2, "M3U stations get a sibling format for comparison")
        XCTAssertEqual(station.streamCandidates[0].pathExtension, "ts")
        XCTAssertEqual(station.streamCandidates[1].pathExtension, "m3u8")
        XCTAssertEqual(station.streamCandidates[0].query, "token=abc")
    }
}
