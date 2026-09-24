import XCTest
@testable import IPTVRadio

/// The channel key is the whole reason the song lookup was failing on device:
/// every attempt came back 404 because the key was being derived from the
/// panel's label, and the two are not related by any rule.
final class SiriusXMChannelKeyTests: XCTestCase {
    func testKnownChannelsResolveFromTheirOwnName() {
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Ozzy's Boneyard"), "ozzysboneyard")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "90s on 9"), "90son9")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Shade 45"), "shade45")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "The Highway"), "thehighway")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Hip-Hop Nation"), "hiphopnation")
    }

    func testKeyIsNotDerivableFromTheName() {
        // The point of the table. No stripping or re-prefixing rule produces
        // these from the label, which is why derivation returned only 404s.
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Fly"), "siriusxmfly")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "2000s"), "pop2k")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Rock The Bells"), "rockthebellsradio")
    }

    func testResolvesThroughPanelDecorations() {
        // The same channel, as three different panels label it.
        for name in ["Radio: SiriusXM FLY", "USA: SXM Fly HD", "SiriusXM Fly"] {
            XCTAssertEqual(
                SiriusXMChannelKeys.key(forStationNamed: name), "siriusxmfly",
                "\(name) should resolve to the same channel"
            )
        }
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "USA MUSIC: Octane HD"), "octane")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "USA: SXM Ozzy's Boneyard HD"), "ozzysboneyard")
    }

    func testIgnoresAccentsAndPunctuation() {
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Flow Nación"), "flownacion")
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "flow nacion"), "flownacion")
    }

    func testKeepsRadioWhenItIsPartOfTheChannelName() {
        // "Radio" is a section label as a prefix and part of the name as a
        // suffix; stripping it as a suffix would lose the only match.
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "E Street Radio"), "estreetradio")
    }

    func testUnknownChannelYieldsNothingRatherThanAGuess() {
        XCTAssertNil(SiriusXMChannelKeys.key(forStationNamed: "Some Local Jazz Station"))
        XCTAssertNil(SiriusXMChannelKeys.key(forStationNamed: "Radio:"))
        XCTAssertNil(SiriusXMChannelKeys.key(forStationNamed: "   "))
    }

    func testShortChannelNamesAreNotMatchedByContainment() {
        // "Spa", "BPM" and "Love" appear inside unrelated names. They resolve
        // only when the whole name is theirs.
        XCTAssertNil(SiriusXMChannelKeys.key(forStationNamed: "Spanish Hits"))
        XCTAssertEqual(SiriusXMChannelKeys.key(forStationNamed: "Spa"), "spa")
    }
}

final class ChannelKeyResolverTests: XCTestCase {
    private func station(_ name: String) -> RadioStation {
        RadioStation(
            name: name,
            streamURL: URL(string: "https://host.example/live/u/p/1.ts")!,
            groupTitle: "Music Radio",
            source: .xtream
        )
    }

    func testKnownChannelComesBeforeGuessesFromTheLabel() {
        let keys = ChannelKeyResolver().keys(for: station("Ozzy's Boneyard"))
        XCTAssertEqual(keys.first, "ozzysboneyard")
        XCTAssertTrue(keys.count > 1, "Derived shapes stay as a fallback for channels the table is missing")
    }

    func testTheListenersOwnKeyWinsOutright() {
        // The escape hatch. Whatever the table and the derivation think, a key
        // typed on the diagnostics screen is tried first.
        let store = SongLookupKeyStore(defaults: makeIsolatedDefaults())
        let s = station("Ozzy's Boneyard")
        store.setKey("bigshow", for: s.id)

        let keys = ChannelKeyResolver(overrides: store).keys(for: s)

        XCTAssertEqual(keys.first, "bigshow")
        XCTAssertTrue(keys.contains("ozzysboneyard"), "The automatic keys stay as fallbacks behind it")
    }

    func testKeysAreDeduplicatedAndBounded() {
        let keys = ChannelKeyResolver().keys(for: station("Shade 45"))
        XCTAssertEqual(Set(keys).count, keys.count, "A key tried twice is a wasted request")
        XCTAssertLessThanOrEqual(keys.count, 5, "This runs every poll for every source")
    }

    func testAnUnusableNameYieldsNoKeys() {
        XCTAssertTrue(ChannelKeyResolver().keys(for: station("   ")).isEmpty)
    }
}

final class SongLookupKeyStoreTests: XCTestCase {
    func testStoresAndClearsPerStation() {
        let store = SongLookupKeyStore(defaults: makeIsolatedDefaults())

        XCTAssertNil(store.key(for: "station-a"))
        store.setKey("octane", for: "station-a")
        store.setKey("lithium", for: "station-b")
        XCTAssertEqual(store.key(for: "station-a"), "octane")
        XCTAssertEqual(store.key(for: "station-b"), "lithium")

        // Empty clears, so the UI field needs no separate delete control.
        store.setKey("   ", for: "station-a")
        XCTAssertNil(store.key(for: "station-a"))
        XCTAssertEqual(store.key(for: "station-b"), "lithium", "Clearing one station must not touch another")
    }

    func testTrimsWhitespaceAroundATypedKey() {
        let store = SongLookupKeyStore(defaults: makeIsolatedDefaults())
        store.setKey("  thehighway \n", for: "station-c")
        XCTAssertEqual(store.key(for: "station-c"), "thehighway")
    }
}

final class XMPlaylistNowPlayingProviderTests: XCTestCase {
    private func station(_ name: String) -> RadioStation {
        RadioStation(
            name: name,
            streamURL: URL(string: "https://host.example/live/u/p/1.ts")!,
            groupTitle: "Music Radio",
            source: .xtream
        )
    }

    func testReadsTheMostRecentPlay() async {
        let http = MockHTTP.client { _ in
            (200, Data("""
            {"results":[
              {"track":{"title":"Nokia","artists":["Drake"]},"timestamp":"2026-09-23T12:00:00Z"},
              {"track":{"title":"Older","artists":["Someone Else"]},"timestamp":"2026-09-23T11:55:00Z"}
            ]}
            """.utf8))
        }
        let provider = XMPlaylistNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Octane"))

        XCTAssertTrue(lookup.isSong)
        XCTAssertEqual(lookup.update?.title, "Nokia")
        XCTAssertEqual(lookup.update?.artist, "Drake")
    }

    func testReportsTheStatusForEachKeyTried() async {
        let http = MockHTTP.client { _ in (404, Data("{}".utf8)) }
        let provider = XMPlaylistNowPlayingProvider(http: http)

        let lookup = await provider.currentSong(for: station("Octane"))

        XCTAssertNil(lookup.update)
        XCTAssertEqual(lookup.note?.contains("octane: HTTP 404"), true)
    }

    func testTwoSourcesFailIndependently() async {
        // The reason this provider exists: one unverifiable endpoint is a
        // single point of failure. A key that 404s at the broadcaster can still
        // resolve here, so the song appears.
        let broadcaster = SiriusXMNowPlayingProvider(
            http: MockHTTP.client { _ in (404, Data("{}".utf8)) }
        )
        let fromBroadcaster = await broadcaster.currentSong(for: station("Octane"))
        XCTAssertNil(fromBroadcaster.update)

        let tracker = XMPlaylistNowPlayingProvider(
            http: MockHTTP.client { _ in
                (200, Data(#"{"results":[{"track":{"title":"Nokia","artists":["Drake"]}}]}"#.utf8))
            }
        )
        let fromTracker = await tracker.currentSong(for: station("Octane"))
        XCTAssertEqual(fromTracker.update?.artist, "Drake")
    }
}
