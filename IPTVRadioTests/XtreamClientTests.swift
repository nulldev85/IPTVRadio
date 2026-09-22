import XCTest
@testable import IPTVRadio

final class XtreamClientTests: XCTestCase {
    func testNormalizeServerInputVariants() {
        XCTAssertEqual(
            XtreamCredentials.normalizeServerInput("http://host.example:8080")?.absoluteString,
            "http://host.example:8080"
        )
        XCTAssertEqual(
            XtreamCredentials.normalizeServerInput("host.example:8080")?.absoluteString,
            "https://host.example:8080"
        )
        XCTAssertEqual(
            XtreamCredentials.normalizeServerInput("http://host.example:8080/player_api.php")?.absoluteString,
            "http://host.example:8080"
        )
        XCTAssertEqual(
            XtreamCredentials.normalizeServerInput("http://host.example:8080/c/")?.absoluteString,
            "http://host.example:8080/c"
        )
        XCTAssertNil(XtreamCredentials.normalizeServerInput("   "))
        XCTAssertNil(XtreamCredentials.normalizeServerInput("!!!not a url///:::"))
    }

    func testAuthenticateSendsCredentialsAndMapsSession() async throws {
        let http = MockHTTP.xtreamClient()
        let client = try XtreamClient(credentials: Fixtures.makeCredentials(), http: http)
        let session = try await client.authenticate()
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertTrue(client.isSecure)
    }

    func testAuthenticateRejectedThrowsUnauthorized() async {
        let http = MockHTTP.xtreamClient(auth: Fixtures.authRejectedJSON)
        let client = try? XtreamClient(credentials: Fixtures.makeCredentials(), http: http)
        do {
            _ = try await client?.authenticate()
            XCTFail("Expected unauthorized")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testHTTP401MapsToUnauthorized() async {
        let http = MockHTTP.client { _ in (401, Data()) }
        let client = try? XtreamClient(credentials: Fixtures.makeCredentials(), http: http)
        do {
            _ = try await client?.authenticate()
            XCTFail("Expected unauthorized")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCategoriesAndStreamsDecode() async throws {
        let http = MockHTTP.xtreamClient()
        let client = try XtreamClient(credentials: Fixtures.makeCredentials(), http: http)
        let categories = try await client.categories()
        let streams = try await client.liveStreams()
        XCTAssertEqual(categories.count, 4)
        XCTAssertEqual(streams.count, 6)
    }

    func testStreamURLBuiltWithCredentialsAndFormat() throws {
        let client = try XtreamClient(credentials: Fixtures.makeCredentials(), http: MockHTTP.xtreamClient())
        let url = client.streamURL(streamID: "8020")
        XCTAssertEqual(url.absoluteString, "https://provider.example.net:8080/live/testuser/testpass/8020.m3u8")
        // Credential-bearing URLs must never be logged; the redactor scrubs them.
        let redactor = Redactor(secrets: ["testuser", "testpass"])
        XCTAssertFalse(redactor.redact(url.absoluteString).contains("testuser"))
        XCTAssertFalse(redactor.redact(url.absoluteString).contains("testpass"))
    }

    func testInvalidServerInputThrows() {
        let bad = XtreamCredentials(serverInput: "::::", username: "u", password: "p")
        XCTAssertThrowsError(try XtreamClient(credentials: bad, http: MockHTTP.xtreamClient()))
    }

    @MainActor
    func testLibraryServiceFullRefreshXtream() async {
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lib-test-\(UUID().uuidString)")
        let service = LibraryService(cache: StationCache(fileStore: JSONFileStore(directory: temp)))
        let store = MemorySecretStore()
        let credentials = CredentialsStore(secrets: store)
        try? await credentials.save(CredentialsStore.StoredCredentials(xtream: Fixtures.makeCredentials(), m3uURL: nil))
        let vm = LibraryViewModel(
            libraryService: service,
            settings: settings,
            credentials: credentials,
            httpClient: MockHTTP.xtreamClient()
        )
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        let stations = vm.radioStations
        XCTAssertTrue(stations.contains { $0.name.contains("SiriusXM Hits 1") })
        XCTAssertFalse(stations.contains { $0.name == "Action Movies HD" })
        XCTAssertEqual(vm.siriusStations.count, 3)
        // Provider artwork (stream_icon) must be retained on the station.
        XCTAssertEqual(
            stations.first { $0.name.contains("SiriusXM Hits 1") }?.logoURL?.absoluteString,
            "https://logo.example/hits1.png"
        )

        // Stream format candidates: audio-only endpoints first (best for
        // radio), then the original MPEG-TS stream, with HLS as fallback.
        let hits = stations.first { $0.name.contains("SiriusXM Hits 1") }
        XCTAssertEqual(hits?.streamCandidates.first?.pathExtension, "mp3")
        XCTAssertEqual(hits?.streamCandidates.map(\.pathExtension), ["mp3", "aac", "ts", "m3u8"])

        // Provider-declared direct sources keep priority and are offered with
        // an HTTPS upgrade plus the original HTTP URL as fallback.
        let faction = stations.first { $0.name == "SXM Faction Talk" }
        XCTAssertEqual(
            faction?.streamCandidates.first?.absoluteString,
            "https://edge.example.net:8042/radio/faction.m3u8"
        )
        XCTAssertTrue(faction?.streamCandidates.contains { $0.absoluteString.hasPrefix("http://") } ?? false)
    }
    @MainActor
    func testHLSFirstPreferenceOrdersCandidates() async {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lib-test-\(UUID().uuidString)")
        let service = LibraryService(cache: StationCache(fileStore: JSONFileStore(directory: temp)))
        let result = await service.refresh(
            credentials: Fixtures.makeCredentials(),
            http: MockHTTP.xtreamClient(),
            rules: .default,
            formatPreference: .hlsFirst
        )
        guard case .success(let snapshot) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        let hits = snapshot.allRadioStations.first { $0.name.contains("SiriusXM Hits 1") }
        XCTAssertEqual(hits?.streamCandidates.map(\.pathExtension), ["mp3", "aac", "m3u8", "ts"],
                       "Audio-only endpoints lead in every mode; the preference orders the muxed streams")
    }

    // MARK: EPG (song info)

    func testShortEPGDecodesListingsWithBase64Title() async throws {
        let base64Title = Data("Daft Punk - Around the World".utf8).base64EncodedString()
        let json = #"{"epg_listings":[{"title":"\#(base64Title)","description":"","start":"2026-09-18 02:00:00","end":"2026-09-18 02:05:00"}]}"#
        let http = MockHTTP.client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("get_short_epg") { return (200, Data(json.utf8)) }
            return (200, Data(Fixtures.authResponseJSON.utf8))
        }
        let client = try XtreamClient(credentials: Fixtures.makeCredentials(), http: http)

        let entries = try await client.shortEPG(streamID: "8020")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(EPGText.decoded(entries.first?.title), "Daft Punk - Around the World")
    }

    func testEPGTextHandlesPlainAndMissingTitles() {
        XCTAssertEqual(EPGText.decoded("Rock The Bells"), "Rock The Bells")
        XCTAssertNil(EPGText.decoded(nil))
        XCTAssertNil(EPGText.decoded("   "))
    }

    @MainActor
    func testXtreamEPGProviderParsesCurrentSong() async throws {
        let base64Title = Data("Daft Punk - Around the World".utf8).base64EncodedString()
        let json = #"{"epg_listings":[{"title":"\#(base64Title)","description":"","start":"","end":""}]}"#
        let http = MockHTTP.client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("get_short_epg") { return (200, Data(json.utf8)) }
            return (404, Data())
        }
        let store = MemorySecretStore()
        let credentials = CredentialsStore(secrets: store)
        try await credentials.save(CredentialsStore.StoredCredentials(xtream: Fixtures.makeCredentials(), m3uURL: nil))
        let provider = XtreamEPGProvider(credentials: credentials, http: http)

        let update = await provider.currentSongInfo(streamID: "8020")
        XCTAssertEqual(update?.artist, "Daft Punk")
        XCTAssertEqual(update?.title, "Around the World")
    }

    // MARK: Which EPG listing is "now"
    //
    // get_short_epg returns listings in ascending start order, so the one on
    // air is at the front. Taking the last one showed the furthest-future show.

    private func entries(_ json: String) -> [XtreamEPGEntry] {
        (try? XtreamDecoder.decodeShortEPG(Data(json.utf8))) ?? []
    }

    private func b64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    func testEPGPrefersTheListingFlaggedNowPlaying() {
        let list = entries("""
        {"epg_listings":[
          {"title":"\(b64("Earlier Show"))","now_playing":0},
          {"title":"\(b64("Current Show"))","now_playing":1},
          {"title":"\(b64("Later Show"))","now_playing":0}
        ]}
        """)
        let current = XtreamEPGProvider.currentEntry(in: list)
        XCTAssertEqual(EPGText.decoded(current?.title), "Current Show")
    }

    func testEPGPicksTheListingCoveringNowByTimestamp() {
        let now = Date().timeIntervalSince1970
        let list = entries("""
        {"epg_listings":[
          {"title":"\(b64("Finished Show"))","start_timestamp":\(Int(now - 7200)),"stop_timestamp":\(Int(now - 3600))},
          {"title":"\(b64("On Air Now"))","start_timestamp":\(Int(now - 60)),"stop_timestamp":\(Int(now + 1800))},
          {"title":"\(b64("Upcoming Show"))","start_timestamp":\(Int(now + 1800)),"stop_timestamp":\(Int(now + 5400))}
        ]}
        """)
        let current = XtreamEPGProvider.currentEntry(in: list)
        XCTAssertEqual(EPGText.decoded(current?.title), "On Air Now")
    }

    func testEPGFallsBackToTheFirstListingNotTheLast() {
        let list = entries("""
        {"epg_listings":[
          {"title":"\(b64("First Listing"))"},
          {"title":"\(b64("Last Listing"))"}
        ]}
        """)
        let current = XtreamEPGProvider.currentEntry(in: list)
        XCTAssertEqual(
            EPGText.decoded(current?.title), "First Listing",
            "With nothing to order by, the front of the list is now, not the back"
        )
    }

    // MARK: Song vs programme

    @MainActor
    private func makeProvider(json: String) async throws -> XtreamEPGProvider {
        let http = MockHTTP.client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("get_short_epg") { return (200, Data(json.utf8)) }
            return (404, Data())
        }
        let credentials = CredentialsStore(secrets: MemorySecretStore())
        try await credentials.save(
            CredentialsStore.StoredCredentials(xtream: Fixtures.makeCredentials(), m3uURL: nil)
        )
        return XtreamEPGProvider(credentials: credentials, http: http)
    }

    @MainActor
    func testEPGProgrammeNameIsReturnedWithoutAnArtist() async throws {
        // A show name is not a track. Returning it with no artist is what keeps
        // it out of the album-art lookup, which would otherwise search the
        // music catalogue for a show title.
        let provider = try await makeProvider(
            json: #"{"epg_listings":[{"title":"\#(b64("The Heat with Mina SayWhat"))","description":""}]}"#
        )
        let update = await provider.currentSongInfo(streamID: "8020")
        XCTAssertEqual(update?.title, "The Heat with Mina SayWhat")
        XCTAssertNil(update?.artist, "A programme name must not be passed off as an artist/title pair")
    }

    @MainActor
    func testEPGDoesNotMineTheDescriptionForASongWhenATitleExists() async throws {
        // Descriptions are prose, and prose contains dashes. Splitting one
        // yields a well-formed artist and title that are not a song at all,
        // which would then be shown as the current track and sent to the music
        // catalogue for album art.
        let provider = try await makeProvider(
            json: #"{"epg_listings":[{"title":"\#(b64("The Heat"))","description":"\#(b64("Hip-hop and R&B - hosted live from Philadelphia"))"}]}"#
        )
        let update = await provider.currentSongInfo(streamID: "8020")
        XCTAssertEqual(update?.title, "The Heat")
        XCTAssertNil(update?.artist, "A programme blurb must not become an artist/title pair")
    }

    @MainActor
    func testEPGUsesTheDescriptionOnlyWhenThereIsNoTitle() async throws {
        let provider = try await makeProvider(
            json: #"{"epg_listings":[{"title":"","description":"\#(b64("Drake - Nokia"))"}]}"#
        )
        let update = await provider.currentSongInfo(streamID: "8020")
        XCTAssertEqual(update?.artist, "Drake")
        XCTAssertEqual(update?.title, "Nokia")
    }
}

/// In-memory secret store for tests; never touches the real Keychain.
final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func saveData(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = data
    }

    func loadData(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    func deleteData(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }
}
