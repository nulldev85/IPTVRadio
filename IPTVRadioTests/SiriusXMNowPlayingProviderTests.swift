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

    func testAddsTheBrandBackForAPanelThatDroppedIt() {
        // The mirror image of stripping it. A panel listing the channel as just
        // "Fly" gives no way to reach a key of "siriusxmfly" unless the brand is
        // put back, and the keys are inconsistent about carrying it.
        XCTAssertEqual(SiriusXMNowPlayingProvider.candidateSlugs(for: "Fly"), ["fly", "siriusxmfly"])
    }

    func testTriesTheNameWithAndWithoutALeadingArticle() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "SiriusXM The Highway"),
            ["siriusxmthehighway", "thehighway", "highway", "siriusxmhighway"],
            "SiriusXM keys the same channel both ways across its own surfaces"
        )
    }

    func testDropsSectionLabelsAndQualitySuffixes() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "USA MUSIC: Octane HD"),
            ["octane", "siriusxmoctane"],
            "Panels label channels for browsing; the section and the quality tag are not part of the name"
        )
    }

    func testBoundsTheNumberOfRequestsPerPoll() {
        XCTAssertLessThanOrEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "SXM: The SiriusXM Heat Radio HD").count, 5,
            "This runs every poll; an unbounded slug list means a burst of requests every 30 seconds"
        )
    }

    func testKeepsDigitsAndDropsSeparators() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "90s on 9"),
            ["90son9", "siriusxm90son9"]
        )
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Hip-Hop Nation"),
            ["hiphopnation", "siriusxmhiphopnation"]
        )
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Ozzy's Boneyard"),
            ["ozzysboneyard", "siriusxmozzysboneyard"]
        )
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Radio: Shade 45"),
            ["shade45", "siriusxmshade45"]
        )
    }

    func testDeduplicatesWhenStrippingChangesNothing() {
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Shade 45"), ["shade45", "siriusxmshade45"],
            "A name with no brand to strip must not yield the same slug twice"
        )
    }

    func testALongPrefixBeforeAColonIsPartOfTheNameNotASectionLabel() {
        // A wrong strip does not merely waste an attempt: it removes the only
        // name that could have matched.
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.candidateSlugs(for: "Classic Rewind Weekend: Live"),
            ["classicrewindweekendlive", "siriusxmclassicrewindweekendlive"]
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

    // MARK: Which play is current

    func testTakesTheNewestPlayWhateverOrderTheListIsIn() {
        // The freeze this fixes. A list of recent plays whose newest entry is
        // last would otherwise report a real song, with real album art, that
        // never changes however long the station runs — indistinguishable from
        // working until you listen for a few minutes.
        let oldestFirst = json("""
        [{"id":"b","timestamp":"2026-09-24T03:36:01.000Z","track":{"title":"Older","artists":[{"name":"Older Artist"}]}},
         {"id":"a","timestamp":"2026-09-24T03:40:12.000Z","track":{"title":"Newer","artists":[{"name":"Newest Artist"}]}}]
        """)
        let newestFirst = json("""
        [{"id":"a","timestamp":"2026-09-24T03:40:12.000Z","track":{"title":"Newer","artists":[{"name":"Newest Artist"}]}},
         {"id":"b","timestamp":"2026-09-24T03:36:01.000Z","track":{"title":"Older","artists":[{"name":"Older Artist"}]}}]
        """)

        XCTAssertEqual(SiriusXMNowPlayingProvider.findSong(in: oldestFirst)?.title, "Newer")
        XCTAssertEqual(
            SiriusXMNowPlayingProvider.findSong(in: newestFirst)?.title, "Newer",
            "The answer must not depend on the order an undocumented source happens to use"
        )
    }

    func testReadsAPlayTimeThatSitsBesideTheTrackRatherThanInsideIt() {
        // `{ timestamp: …, track: { … } }` is the common shape: the time is the
        // track's sibling, so the walk has to carry it down.
        let payload = json("""
        {"results":[{"playedAt":1758684001000,"song":{"name":"Older","artist":"Older Artist"}},
                    {"playedAt":1758684612000,"song":{"name":"Newer","artist":"Newest Artist"}}]}
        """)
        XCTAssertEqual(SiriusXMNowPlayingProvider.findSong(in: payload)?.artist, "Newest Artist")
    }

    func testAcceptsEpochSecondsAndTheBroadcastersOwnDateSpelling() {
        let epochSeconds = json("""
        {"plays":[{"start":"1758684612","song":{"name":"Newer","artist":"Newest Artist"}},
                  {"start":"1758684001","song":{"name":"Older","artist":"Older Artist"}}]}
        """)
        XCTAssertEqual(SiriusXMNowPlayingProvider.findSong(in: epochSeconds)?.artist, "Newest Artist")

        let broadcaster = json("""
        {"channelMetadataResponse":{"metaData":{"currentEvent":{
          "startTime":"2026-09-24-03:40:12",
          "song":{"name":"Nokia","artists":[{"name":"Drake"}]}}}}}
        """)
        let play = SiriusXMNowPlayingProvider.findSong(in: broadcaster)
        XCTAssertEqual(play?.artist, "Drake")
        XCTAssertNotNil(play?.playedAt, "The broadcaster spells its timestamps its own way, and they still count")
    }

    func testFallsBackToTheFirstPlayWhenNothingIsTimestamped() {
        let payload = json("""
        {"events":[{"channel":"The Heat"},{"song":{"title":"Nokia","artist":"Drake"}}]}
        """)
        let play = SiriusXMNowPlayingProvider.findSong(in: payload)
        XCTAssertEqual(play?.artist, "Drake")
        XCTAssertNil(play?.playedAt)
    }

    func testIgnoresValuesUnderDateKeysThatAreNotDates() {
        // `date` and `time` are broad keys; anything that does not parse must
        // leave the play undated rather than inventing an ordering.
        let payload = json("""
        {"plays":[{"date":"yesterday","song":{"name":"Only","artist":"Only Artist"}}]}
        """)
        let play = SiriusXMNowPlayingProvider.findSong(in: payload)
        XCTAssertEqual(play?.artist, "Only Artist")
        XCTAssertNil(play?.playedAt)
    }

    func testTheMatchedNoteCarriesTheAgeOfThePlay() {
        // How a frozen song is spotted from a screenshot: the age keeps growing
        // while the audio moves on.
        let now = Date()
        let play = SiriusXMNowPlayingProvider.Play(
            title: "Nokia", artist: "Drake", playedAt: now.addingTimeInterval(-42)
        )
        let note = SiriusXMNowPlayingProvider.matchedNote(key: "fly", play: play, now: now)
        XCTAssertTrue(note.hasPrefix("fly: matched, play from "), note)
        XCTAssertTrue(note.hasSuffix("(42s ago)"), note)

        XCTAssertEqual(SiriusXMNowPlayingProvider.age(of: now.addingTimeInterval(-600), now: now), "10m ago")
        XCTAssertEqual(SiriusXMNowPlayingProvider.age(of: now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    func testAnUndatedMatchSaysSoRatherThanClaimingATime() {
        let play = SiriusXMNowPlayingProvider.Play(title: "Nokia", artist: "Drake", playedAt: nil)
        XCTAssertEqual(SiriusXMNowPlayingProvider.matchedNote(key: "fly", play: play), "fly: matched")
    }

    func testUnrecognisedShapeYieldsNothingRatherThanAGuess() {
        XCTAssertNil(SiriusXMNowPlayingProvider.findSong(in: json(#"{"status":"ok","code":200}"#)))
        XCTAssertNil(SiriusXMNowPlayingProvider.findSong(in: json("[]")))
    }

    // MARK: Reporting
    private func station(_ name: String) -> RadioStation {
        RadioStation(
            name: name,
            streamURL: URL(string: "https://host.example/live/u/p/1.ts")!,
            groupTitle: "Music Radio",
            source: .xtream
        )
    }

    func testReportsTheHTTPStatusForEachChannelKeyTried() async {
        // With no published list of channel keys this trail is the diagnosis:
        // 404 means the guess is wrong, 403 means the host refused, and a 200
        // with no song means the key is right and nothing is playing. The app
        // is installed from CI artifacts with no console attached, so a status
        // that is not reported cannot be observed at all.
        let http = MockHTTP.client { _ in (404, Data("{}".utf8)) }
        let provider = SiriusXMNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Radio: SiriusXM FLY"))

        XCTAssertNil(lookup.update)
        XCTAssertEqual(lookup.note, "siriusxmfly: HTTP 404, fly: HTTP 404")
    }

    func testReportsAChannelKeyThatAnsweredWithoutASong() async {
        let http = MockHTTP.client { _ in (200, Data(#"{"channelMetadataResponse":{}}"#.utf8)) }
        let provider = SiriusXMNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Ozzy's Boneyard"))

        XCTAssertNil(lookup.update)
        XCTAssertEqual(
            lookup.note, "ozzysboneyard: no song in response, siriusxmozzysboneyard: no song in response",
            "A key that answers is a different problem from a key that 404s, and has to read differently"
        )
        XCTAssertTrue(
            lookup.reachedSource,
            "The channel matched and is between songs; a source like that must keep being asked"
        )
    }

    func testAKeyThatWasRefusedDoesNotCountAsReachingTheSource() async {
        let http = MockHTTP.client { _ in (403, Data("{}".utf8)) }
        let provider = SiriusXMNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Radio: SiriusXM FLY"))

        XCTAssertFalse(
            lookup.reachedSource,
            "Refused every key: this is the case the engine is entitled to give up on"
        )
    }

    func testAMatchReportsWhichKeyAnsweredAndHowOldThePlayIs() async {
        let http = MockHTTP.client { _ in
            (200, Data(#"{"currentEvent":{"songName":"Nokia","artistName":"Drake"}}"#.utf8))
        }
        let provider = SiriusXMNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Radio: SiriusXM FLY"))

        XCTAssertTrue(lookup.isSong)
        XCTAssertEqual(lookup.update?.artist, "Drake")
        XCTAssertEqual(lookup.update?.title, "Nokia")
        XCTAssertEqual(
            lookup.note, "siriusxmfly: matched",
            "Which key answered is worth reporting even on success — and with a timestamped play, its age"
        )
    }

    func testAnUnusableStationNameSaysSoRatherThanSilentlyDoingNothing() async {
        let http = MockHTTP.client { _ in (200, Data("{}".utf8)) }
        let provider = SiriusXMNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("   "))

        XCTAssertEqual(lookup.note, "station name yields no channel key")
    }
}
