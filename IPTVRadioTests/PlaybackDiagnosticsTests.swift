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

    func testSnapshotCarriesCodecAndDirectSourceFlag() {
        let snapshot = PlaybackDiagnostics.snapshot(
            streamExtension: "ts",
            usesDirectSource: true,
            events: [
                PlaybackDiagnostics.EventSample(
                    indicatedBitrate: 320_000,
                    observedBitrate: 310_000,
                    averageAudioBitrate: 320_000,
                    numberOfMediaRequests: 3
                )
            ],
            tracks: [
                PlaybackDiagnostics.TrackSample(
                    mediaType: "soun",
                    estimatedDataRate: 320_000,
                    codec: "MP3",
                    sampleRate: 44_100,
                    channelCount: 2
                )
            ]
        )
        XCTAssertEqual(snapshot.streamExtension, "ts")
        XCTAssertTrue(snapshot.usesDirectSource)
        XCTAssertEqual(snapshot.codec, "MP3")
        XCTAssertEqual(snapshot.sampleRate, 44_100)
        XCTAssertEqual(snapshot.channelCount, 2)
        XCTAssertEqual(snapshot.indicatedBitrate, 320_000)
        XCTAssertEqual(snapshot.observedBitrate, 310_000)
    }

    func testSnapshotDefaultsUnknownExtensionAndMissingTrack() {
        let snapshot = PlaybackDiagnostics.snapshot(
            streamExtension: "",
            usesDirectSource: false,
            events: [],
            tracks: []
        )
        XCTAssertEqual(snapshot.streamExtension, "unknown")
        XCTAssertFalse(snapshot.usesDirectSource)
        XCTAssertNil(snapshot.codec)
        XCTAssertNil(snapshot.indicatedBitrate)
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
}
