import XCTest
@testable import IPTVRadio

final class HLSManifestParserTests: XCTestCase {
    private let baseURL = URL(string: "https://cdn.example.net/live/12345.m3u8")!

    func testPicksHighestBandwidthAudioOnlyCandidate() {
        let master = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",DEFAULT=YES,URI="audio/eng.m3u8",BANDWIDTH=128000
        #EXT-X-STREAM-INF:BANDWIDTH=5324800,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="aac"
        video/720p.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2",AUDIO="aac"
        audio/128k.m3u8
        """
        let result = HLSManifestParser.parse(master, baseURL: baseURL)
        XCTAssertEqual(result.audioOnlyURL?.absoluteString, "https://cdn.example.net/live/audio/128k.m3u8")
        XCTAssertEqual(result.declaredAudioBandwidth, 160_000)
        XCTAssertEqual(result.variantCount, 2)
        XCTAssertEqual(result.audioRenditionCount, 1)
    }

    func testFallsBackToAudioRenditionWhenNoAudioOnlyVariant() {
        let master = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",DEFAULT=YES,URI="https://audio.example.net/eng.m3u8",BANDWIDTH=96000
        #EXT-X-STREAM-INF:BANDWIDTH=5324800,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="aac"
        video/720p.m3u8
        """
        let result = HLSManifestParser.parse(master, baseURL: baseURL)
        XCTAssertEqual(result.audioOnlyURL?.absoluteString, "https://audio.example.net/eng.m3u8")
        XCTAssertEqual(result.declaredAudioBandwidth, 96_000)
        XCTAssertEqual(result.variantCount, 1)
        XCTAssertEqual(result.audioRenditionCount, 1)
    }

    func testMediaPlaylistHasNoAudioOnlyRendition() {
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:10.0,
        segment0.ts
        #EXTINF:10.0,
        segment1.ts
        """
        let result = HLSManifestParser.parse(media, baseURL: baseURL)
        XCTAssertNil(result.audioOnlyURL)
        XCTAssertEqual(result.variantCount, 0)
        XCTAssertEqual(result.audioRenditionCount, 0)
    }

    func testVideoOnlyMasterHasNoAudioOnlyRendition() {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5324800,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        video/720p.m3u8
        """
        let result = HLSManifestParser.parse(master, baseURL: baseURL)
        XCTAssertNil(result.audioOnlyURL)
        XCTAssertEqual(result.variantCount, 1)
    }

    func testMissingCodecsIsNotTreatedAsAudioOnly() {
        // Conservative: without codec information we cannot be sure a variant
        // is audio-only, so the app keeps the provider's URL unchanged.
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=64000
        unknown.m3u8
        """
        let result = HLSManifestParser.parse(master, baseURL: baseURL)
        XCTAssertNil(result.audioOnlyURL)
    }

    func testQuotedAttributeCommasDoNotBreakParsing() {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5324800,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1920x1080
        video/1080p.m3u8
        """
        let result = HLSManifestParser.parse(master, baseURL: baseURL)
        XCTAssertNil(result.audioOnlyURL, "A/variant with video codecs and resolution is not audio-only")
        XCTAssertEqual(result.variantCount, 1)
    }
}
