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
        XCTAssertEqual(hits?.streamCandidates.map(\.pathExtension), ["m3u8", "ts", "mp3", "aac"])
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
