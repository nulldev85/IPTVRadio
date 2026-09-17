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
    }

    /// The provider's own direct_source URL — usually the unmodified
    /// source feed — must be preferred over the app's constructed /live/
    /// endpoint, and the station must record that it was used.
    @MainActor
    func testLibraryServicePrefersDirectSourceAndFlagsIt() async {
        let (service, vm) = await makeLibraryServiceHarness()
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        let station = vm.siriusStations.first { $0.name == "SXM Faction Talk" }
        // The provider's own http direct_source is upgraded to https because
        // the portal itself is https (see upgradeToHTTPSIfPossible).
        XCTAssertEqual(station?.streamURL.absoluteString, "https://edge.example.net:8042/radio/faction.m3u8")
        XCTAssertEqual(station?.usesDirectSource, true)
        _ = service
    }

    /// When there is no direct_source, a provider-declared container_extension
    /// (e.g. "ts") must decide the endpoint format instead of a hardcoded
    /// ".m3u8" — many Xtream panels transcode .m3u8 to a fixed, lower audio
    /// bitrate while other containers are passed through unmodified.
    @MainActor
    func testLibraryServiceUsesProviderContainerExtensionWhenNoDirectSource() async {
        let streamsJSON = #"""
        [{"num": 1, "name": "SiriusXM Test Channel", "stream_type": "radio", "stream_id": "7001", "category_id": "1", "direct_source": "", "container_extension": "ts"}]
        """#
        let (_, vm) = await makeLibraryServiceHarness(streams: streamsJSON)
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        let station = vm.siriusStations.first { $0.name == "SiriusXM Test Channel" }
        XCTAssertEqual(station?.streamURL.pathExtension, "ts")
        XCTAssertEqual(station?.usesDirectSource, false)
    }

    /// An unrecognized/malformed container_extension must never build a
    /// broken URL; the app falls back to the known-good default.
    @MainActor
    func testLibraryServiceIgnoresUnknownContainerExtension() async {
        let streamsJSON = #"""
        [{"num": 1, "name": "SiriusXM Test Channel", "stream_type": "radio", "stream_id": "7002", "category_id": "1", "direct_source": "", "container_extension": "<script>"}]
        """#
        let (_, vm) = await makeLibraryServiceHarness(streams: streamsJSON)
        await vm.refresh()
        XCTAssertEqual(vm.state, .loaded)
        let station = vm.siriusStations.first { $0.name == "SiriusXM Test Channel" }
        XCTAssertEqual(station?.streamURL.pathExtension, "m3u8")
    }

    func testSanitizedContainerExtensionOnlyAllowsKnownFormats() {
        XCTAssertEqual(LibraryService.sanitizedContainerExtension("TS"), "ts")
        XCTAssertEqual(LibraryService.sanitizedContainerExtension(" m3u8 "), "m3u8")
        XCTAssertNil(LibraryService.sanitizedContainerExtension("exe"))
        XCTAssertNil(LibraryService.sanitizedContainerExtension(nil))
        XCTAssertNil(LibraryService.sanitizedContainerExtension(""))
    }

    @MainActor
    private func makeLibraryServiceHarness(
        streams: String = Fixtures.liveStreamsJSON
    ) async -> (LibraryService, LibraryViewModel) {
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
            httpClient: MockHTTP.xtreamClient(streams: streams)
        )
        return (service, vm)
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
