import XCTest
@testable import IPTVRadio

final class PlaybackDiagnosticsTests: XCTestCase {
    func testSummaryIncludesStreamTypeAndBitrates() {
        let summary = PlaybackDiagnostics.summary(
            streamExtension: "m3u8",
            events: [
                PlaybackDiagnostics.EventSample(
                    indicatedBitrate: 256_000,
                    observedBitrate: 240_700,
                    averageAudioBitrate: 128_000,
                    numberOfMediaRequests: 5
                )
            ],
            tracks: [
                PlaybackDiagnostics.TrackSample(mediaType: "soun", estimatedDataRate: 131_000)
            ]
        )
        XCTAssertTrue(summary.contains("streamType=m3u8"))
        XCTAssertTrue(summary.contains("hlsIndicatedBitrate=256kbps"))
        XCTAssertTrue(summary.contains("observedBitrate=241kbps"))
        XCTAssertTrue(summary.contains("averageAudioBitrate=128kbps"))
        XCTAssertTrue(summary.contains("audioTrackDataRate=131kbps"))
        XCTAssertTrue(summary.contains("mediaRequests=5"))
        XCTAssertTrue(summary.contains("qualityDeterminedBySource"))
    }

    func testSummaryNeverContainsURLsOrCredentialMaterial() {
        let summary = PlaybackDiagnostics.summary(
            streamExtension: "m3u8",
            events: [
                PlaybackDiagnostics.EventSample(
                    indicatedBitrate: 96_000, observedBitrate: 90_000,
                    averageAudioBitrate: 64_000, numberOfMediaRequests: 2
                )
            ],
            tracks: [PlaybackDiagnostics.TrackSample(mediaType: "soun", estimatedDataRate: 64_000)]
        )
        XCTAssertFalse(summary.lowercased().contains("http"))
        XCTAssertFalse(summary.contains("://"))
        XCTAssertFalse(summary.contains("username"))
        XCTAssertFalse(summary.contains("password"))
        XCTAssertFalse(summary.contains("/live/"))
    }

    func testSummaryHandlesEmptyAccessLog() {
        let summary = PlaybackDiagnostics.summary(streamExtension: "mp3", events: [], tracks: [])
        XCTAssertTrue(summary.contains("streamType=mp3"))
        XCTAssertTrue(summary.contains("noAccessLogEvents"))
        XCTAssertTrue(summary.contains("qualityDeterminedBySource"))
    }

    func testSummaryIgnoresVideoTracksAndZeroBitrates() {
        let summary = PlaybackDiagnostics.summary(
            streamExtension: "",
            events: [
                PlaybackDiagnostics.EventSample(
                    indicatedBitrate: 0, observedBitrate: 0,
                    averageAudioBitrate: nil, numberOfMediaRequests: nil
                )
            ],
            tracks: [
                PlaybackDiagnostics.TrackSample(mediaType: "vide", estimatedDataRate: 500_000),
                PlaybackDiagnostics.TrackSample(mediaType: "soun", estimatedDataRate: 0),
            ]
        )
        XCTAssertTrue(summary.contains("streamType=unknown"))
        XCTAssertFalse(summary.contains("hlsIndicatedBitrate"))
        XCTAssertFalse(summary.contains("audioTrackDataRate"))
    }

    // MARK: Audio format description

    private func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    func testAudioFormatDescriberMapsCommonCodecs() {
        XCTAssertEqual(
            AudioFormatDescriber.describe(codec: fourCC("aac "), sampleRate: 44_100, channels: 2),
            "AAC-LC · 44.1 kHz · stereo"
        )
        XCTAssertEqual(
            AudioFormatDescriber.describe(codec: fourCC("aacp"), sampleRate: 24_000, channels: 2),
            "HE-AAC · 24.0 kHz · stereo"
        )
        XCTAssertEqual(
            AudioFormatDescriber.describe(codec: fourCC("mp3 "), sampleRate: 0, channels: 1),
            "MP3 · mono"
        )
        XCTAssertEqual(
            AudioFormatDescriber.describe(codec: fourCC("ec-3"), sampleRate: 48_000, channels: 6),
            "E-AC-3 · 48.0 kHz · 6 ch"
        )
    }

    func testSummaryIncludesAudioFormatWhenKnown() {
        let sample = PlaybackDiagnostics.makeSample(
            streamExtension: "m3u8",
            events: [],
            tracks: [],
            audioFormatDescription: "HE-AAC · 24.0 kHz · stereo"
        )
        XCTAssertTrue(PlaybackDiagnostics.summary(for: sample).contains("audioFormat=HE-AAC"))
        XCTAssertFalse(PlaybackDiagnostics.summary(for: sample).lowercased().contains("http"))
    }
}
