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

    func testRecentIHeartHistoryBridgesFeedDelay() {
        let now = Date(timeIntervalSince1970: 2_000)
        let recent = ManualRadioNowPlayingProvider.Track(
            title: "Recent", artist: "Singer", imagePath: nil, startTime: 1_800, endTime: 1_930
        )
        XCTAssertEqual(
            ManualRadioNowPlayingProvider.currentTrack(in: [recent], now: now)?.title,
            "Recent"
        )
        XCTAssertNil(ManualRadioNowPlayingProvider.currentTrack(
            in: [recent], now: Date(timeIntervalSince1970: 2_200)
        ))
    }

    func testParsesICYTitleWithoutPadding() {
        let block = Data("StreamTitle='Tame Impala - The Less I Know The Better  ';\0\0".utf8)
        XCTAssertEqual(
            ICYMetadataReader.title(from: block),
            "Tame Impala - The Less I Know The Better"
        )
    }

    func testParsesDoubleQuotedMixedCaseICYTitle() {
        let block = Data("streamtitle = \"The Weeknd – Blinding Lights\";\0".utf8)
        XCTAssertEqual(ICYMetadataReader.title(from: block), "The Weeknd – Blinding Lights")
    }

    func testParsesApostropheInsideICYTitle() {
        let block = Data("StreamTitle='Hall & Oates - I Can't Go for That';\0".utf8)
        XCTAssertEqual(ICYMetadataReader.title(from: block), "Hall & Oates - I Can't Go for That")
    }

    func testGenericICYStationBehindM3UPlaylist() async {
        let http = MockHTTP.client { _ in
            (200, Data("#EXTM3U\nhttps://radio.example.org/live.aac\n".utf8))
        }
        let provider = ManualRadioNowPlayingProvider(http: http) { url in
            url.path == "/live.aac" ? "Daft Punk – Digital Love" : nil
        }
        let station = RadioStation(
            name: "My Radio",
            streamURL: URL(string: "https://radio.example.org/listen.m3u")!,
            source: .manual
        )
        let result = await provider.currentSong(for: station)
        XCTAssertEqual(result.update?.artist, "Daft Punk")
        XCTAssertEqual(result.update?.title, "Digital Love")
    }

    func testGenericIHeartStationID() {
        XCTAssertEqual(
            KnownManualStation.iHeartID(for: URL(string: "https://stream.revma.ihrhls.com/zc987/hls.m3u8")!),
            987
        )
    }

    func testIHeartProviderReturnsCurrentSongAndArtwork() async {
        let now = Int(Date().timeIntervalSince1970)
        let imageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let response = """
        {"data":[{"title":"Current Song","artist":"Test Artist",\
        "imagePath":"http://images.example.org/cover.jpg",\
        "startTime":\(now - 30),"endTime":\(now + 120)}]}
        """
        let http = MockHTTP.client { request in
            if request.url?.path.contains("trackHistory") == true {
                return (200, Data(response.utf8))
            }
            return (200, imageData)
        }
        let provider = ManualRadioNowPlayingProvider(http: http)
        let station = RadioStation(
            name: "B95",
            streamURL: URL(string: "https://stream.revma.ihrhls.com/zc141/hls.m3u8")!,
            source: .manual
        )
        let result = await provider.currentSong(for: station)
        XCTAssertEqual(result.update?.title, "Current Song")
        XCTAssertEqual(result.update?.artist, "Test Artist")
        XCTAssertEqual(result.update?.artworkData, imageData)
    }

    func testIHeartCandidateBypassesUnavailablePlaylist() async {
        let now = Int(Date().timeIntervalSince1970)
        let response = """
        {"data":[{"title":"Fresh Track","artist":"Test Artist",\
        "imagePath":null,"startTime":\(now - 30),"endTime":\(now + 120)}]}
        """
        let http = MockHTTP.client { request in
            if request.url?.path.contains("trackHistory") == true {
                return (200, Data(response.utf8))
            }
            return (404, Data())
        }
        let station = RadioStation(
            name: "B95",
            streamURL: URL(string: "https://radio.example.org/listen.m3u")!,
            source: .manual,
            alternativeStreamURLs: [URL(string: "https://stream.revma.ihrhls.com/zc141/hls.m3u8")!]
        )
        let result = await ManualRadioNowPlayingProvider(http: http).currentSong(for: station)
        XCTAssertEqual(result.update?.title, "Fresh Track")
        XCTAssertEqual(result.update?.artist, "Test Artist")
    }

    func testTriesAlternativeStreamWhenFirstHasNoICYMetadata() async {
        let http = MockHTTP.client { _ in (404, Data()) }
        let station = RadioStation(
            name: "Local radio",
            streamURL: URL(string: "https://radio.example.org/primary.aac")!,
            source: .manual,
            alternativeStreamURLs: [URL(string: "https://radio.example.org/backup.aac")!]
        )
        let provider = ManualRadioNowPlayingProvider(http: http) { url in
            url.path == "/backup.aac" ? "Artist - Song" : nil
        }
        let result = await provider.currentSong(for: station)
        XCTAssertEqual(result.update?.artist, "Artist")
        XCTAssertEqual(result.update?.title, "Song")
    }
}
