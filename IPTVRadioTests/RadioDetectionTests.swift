import XCTest
@testable import IPTVRadio

final class RadioDetectionTests: XCTestCase {
    let detector = RadioStationDetector(rules: .default)

    private func channel(_ name: String, group: String, path: String, tvg: String? = nil) -> RawChannel {
        RawChannel(
            name: name,
            url: URL(string: "https://edge.example.net\(path)")!,
            group: group,
            tvgID: tvg,
            source: .xtream
        )
    }

    func testSiriusGroupDetectedAsRadioAndSirius() {
        let verdict = detector.classify(channel("SiriusXM Hits 1", group: "SiriusXM", path: "/live/8020.m3u8"))
        XCTAssertTrue(verdict.isRadio)
        XCTAssertTrue(verdict.isSirius)
        XCTAssertGreaterThan(verdict.radioScore, 3)
    }

    func testVideoGroupExcluded() {
        let verdict = detector.classify(channel("Action Movies HD", group: "Movies", path: "/live/5001.mkv"))
        XCTAssertFalse(verdict.isRadio)
        XCTAssertFalse(verdict.isSirius)
    }

    func testRadioKeywordInNameDetected() {
        let verdict = detector.classify(channel("Classic Rock Radio", group: "Entertainment", path: "/live/9001.mp3"))
        XCTAssertTrue(verdict.isRadio)
    }

    func testAudioExtensionAloneQualifies() {
        let verdict = detector.classify(channel("Unknown Stream 42", group: "Whatever", path: "/live/42.aac"))
        XCTAssertTrue(verdict.isRadio, "A clear audio extension should qualify on its own")
    }

    func testVideoExtensionExcluded() {
        let verdict = detector.classify(channel("Random Stream", group: "Whatever", path: "/live/42.mkv"))
        XCTAssertFalse(verdict.isRadio)
    }

    /// Xtream providers commonly serve pure-audio "radio" entries over a
    /// ".ts" (MPEG transport stream) passthrough endpoint to avoid the
    /// bitrate loss of HLS transcoding. ".ts" must not be treated as a
    /// video signal for this source, or picking that endpoint for quality
    /// would make the station disappear from detection.
    func testXtreamTransportStreamExtensionNotPenalizedAsVideo() {
        let verdict = detector.classify(channel("Unknown Stream 42", group: "Whatever", path: "/live/testuser/testpass/42.ts"))
        XCTAssertTrue(verdict.isRadio, "A .ts Xtream endpoint alone should qualify, same as .m3u8 does")
    }

    /// The same extension in an M3U playlist still names a real file and
    /// commonly indicates a recorded TV file, so it keeps the video penalty.
    func testM3UTransportStreamExtensionStillPenalizedAsVideo() {
        let verdict = detector.classify(
            RawChannel(
                name: "Random Stream",
                url: URL(string: "https://edge.example.net/movies/42.ts")!,
                group: "Whatever",
                source: .m3u
            )
        )
        XCTAssertFalse(verdict.isRadio)
    }

    func testTVGIDRadioHintNotSufficientAlone() {
        let verdict = detector.classify(channel("The Mix 88", group: "General", path: "/live/88.stream", tvg: "radio-mix-88"))
        // TVG hint (+1) alone stays below the minimum score of 2.
        XCTAssertGreaterThan(verdict.radioScore, 0)
        XCTAssertFalse(verdict.isRadio)
    }

    func testSnapshotSeparatesSiriusAndRadio() {
        let channels = [
            channel("SiriusXM Hits 1", group: "SiriusXM", path: "/live/8020.m3u8"),
            channel("SiriusXM Octane", group: "SiriusXM", path: "/live/8021.m3u8"),
            channel("Jazz Cafe Radio", group: "Music Radio", path: "/live/9002.mp3"),
            channel("Blockbuster HD", group: "Movies", path: "/live/5001.mkv"),
        ]
        let snapshot = detector.buildSnapshot(channels: channels)
        XCTAssertEqual(snapshot.siriusStations.count, 2)
        XCTAssertEqual(snapshot.radioStations.count, 1)
        XCTAssertEqual(snapshot.totalChannelsScanned, 4)
        XCTAssertTrue(snapshot.allRadioStations.contains { $0.name == "Jazz Cafe Radio" })
    }

    func testSnapshotDropsVideoAndKeepsCategories() {
        let snapshot = detector.buildSnapshot(channels: [
            channel("News Talk 101", group: "Talk Radio", path: "/live/9004.mp3"),
            channel("Late Night Talk Radio", group: "Talk Radio", path: "/live/9006.mp3"),
        ])
        XCTAssertEqual(snapshot.allRadioStations.count, 2)
        XCTAssertTrue(snapshot.categories.contains { CategoryNormalizer.matches("Talk Radio", category: $0) })
    }

    func testSnapshotStationsInCategory() throws {
        let snapshot = detector.buildSnapshot(channels: [
            channel("Jazz Cafe Radio", group: "Music Radio", path: "/live/9002.mp3"),
            channel("Rock Legends", group: "Rock", path: "/live/9005.aacp"),
        ])
        let category = try XCTUnwrap(snapshot.categories.first { $0.name == "Music Radio" })
        let stations = snapshot.stations(in: category)
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations.first?.name, "Jazz Cafe Radio")
    }

    // MARK: Sirius matching

    func testSiriusMatcherScoringWeights() {
        XCTAssertEqual(SiriusMatcher.score(name: "SiriusXM Hits 1", group: "", tvgID: nil, keywords: RadioDetectionRules.default.siriusKeywords), 3)
        XCTAssertEqual(SiriusMatcher.score(name: "Unknown", group: "SiriusXM", tvgID: nil, keywords: RadioDetectionRules.default.siriusKeywords), 2)
        XCTAssertEqual(SiriusMatcher.score(name: "Unknown", group: "", tvgID: "sxm-42", keywords: RadioDetectionRules.default.siriusKeywords), 1)
        XCTAssertEqual(SiriusMatcher.score(name: "Jazz Cafe", group: "Music", tvgID: nil, keywords: RadioDetectionRules.default.siriusKeywords), 0)
    }

    func testSiriusMatcherCaseInsensitive() {
        XCTAssertEqual(SiriusMatcher.score(name: "SXM DRIVE", group: "", tvgID: nil, keywords: ["sxm"]), 3)
        XCTAssertEqual(SiriusMatcher.score(name: "sirius xm pops", group: "", tvgID: nil, keywords: ["sirius xm"]), 3)
    }

    func testSiriusMatcherCustomKeywords() {
        let score = SiriusMatcher.score(name: "Howard Stern Show", group: "", tvgID: nil, keywords: ["howard stern"])
        XCTAssertEqual(score, 3)
    }

    func testSiriusMatcherEmptyKeywordsNeverMatches() {
        XCTAssertEqual(SiriusMatcher.score(name: "SiriusXM", group: "SiriusXM", tvgID: "sxm", keywords: []), 0)
    }

    // MARK: Deduplication

    func testDeduplicatesIdenticalURLs() {
        let a = RadioStation(name: "Station A", streamURL: URL(string: "https://host/stream/1.mp3")!, groupTitle: "Music", source: .m3u)
        let b = RadioStation(name: "Station A (HD)", streamURL: URL(string: "https://host/stream/1.mp3")!, groupTitle: "Music", source: .m3u)
        let result = StationDeduplicator.deduplicate([a, b])
        XCTAssertEqual(result.count, 1)
    }

    func testDeduplicatesCaseAndTrailingSlashURLs() {
        let a = RadioStation(name: "Station A", streamURL: URL(string: "https://HOST/stream/1.mp3")!, groupTitle: "Music", source: .m3u)
        let b = RadioStation(name: "Station A", streamURL: URL(string: "https://host/stream/1.mp3/")!, groupTitle: "Music", source: .m3u)
        XCTAssertEqual(StationDeduplicator.deduplicate([a, b]).count, 1)
    }

    func testSameNameDifferentHostsKept() {
        let a = RadioStation(name: "News Radio", streamURL: URL(string: "https://host1/stream.mp3")!, source: .m3u)
        let b = RadioStation(name: "News Radio", streamURL: URL(string: "https://host2/stream.mp3")!, source: .m3u)
        XCTAssertEqual(StationDeduplicator.deduplicate([a, b]).count, 2)
    }

    func testMergePrefersLogoAndGroup() {
        let a = RadioStation(name: "Station X", streamURL: URL(string: "https://host/x.mp3")!, groupTitle: "", source: .m3u)
        let b = RadioStation(name: "Station X", streamURL: URL(string: "https://host/x.mp3")!, groupTitle: "Music", logoURL: URL(string: "https://host/logo.png")!, source: .m3u)
        let result = StationDeduplicator.deduplicate([a, b])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].groupTitle, "Music")
        XCTAssertEqual(result[0].logoURL?.absoluteString, "https://host/logo.png")
    }

    func testDeduplicatePreservesOrder() {
        let a = RadioStation(name: "First", streamURL: URL(string: "https://host/1.mp3")!, source: .m3u)
        let b = RadioStation(name: "Second", streamURL: URL(string: "https://host/2.mp3")!, source: .m3u)
        let c = RadioStation(name: "First", streamURL: URL(string: "https://host/1.mp3?dup")!, source: .m3u)
        let result = StationDeduplicator.deduplicate([a, b, c])
        XCTAssertEqual(result.map(\.name), ["First", "Second"])
    }

    func testLargePlaylistDetectionCompletes() {
        let channels = (0..<10_000).map { index -> RawChannel in
            let isVideo = index % 2 == 0
            return RawChannel(
                name: isVideo ? "Movie \(index)" : "Radio \(index)",
                url: URL(string: "https://edge.example.net/live/\(index).\(isVideo ? "mkv" : "mp3")")!,
                group: isVideo ? "Movies" : "Music Radio",
                source: .m3u
            )
        }
        let snapshot = detector.buildSnapshot(channels: channels)
        XCTAssertGreaterThan(snapshot.radioStations.count, 4_000)
        XCTAssertFalse(snapshot.allRadioStations.contains { $0.name.hasPrefix("Movie ") })
    }
}
