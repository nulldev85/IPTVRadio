import XCTest
@testable import IPTVRadio

/// A client that never answers, to prove the library can never stay stuck.
struct HangingHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw ProviderError.timedOut
    }
}

@MainActor
final class LibraryLoadingRobustnessTests: XCTestCase {
    private func makeViewModel(
        httpClient: HTTPClient,
        timeout: TimeInterval,
        folder: String
    ) async -> LibraryViewModel {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(folder)-\(UUID().uuidString)")
        let service = LibraryService(cache: StationCache(fileStore: JSONFileStore(directory: temp)))
        let store = MemorySecretStore()
        let credentials = CredentialsStore(secrets: store)
        try? await credentials.save(CredentialsStore.StoredCredentials(xtream: Fixtures.makeCredentials(), m3uURL: nil))
        return LibraryViewModel(
            libraryService: service,
            settings: settings,
            credentials: credentials,
            httpClient: httpClient,
            refreshTimeout: timeout
        )
    }

    func testHungProviderFetchCannotLeaveUIStuckLoading() async {
        let viewModel = await makeViewModel(
            httpClient: HangingHTTPClient(),
            timeout: 0.3,
            folder: "stuck"
        )

        await viewModel.refresh()

        // The UI must have left idle/loading with an actionable message.
        switch viewModel.state {
        case .error(let message):
            XCTAssertTrue(message.lowercased().contains("too long"), "Got: \(message)")
        default:
            XCTFail("Expected a terminal error state, got \(viewModel.state)")
        }
    }

    func testConcurrentRefreshJoinsInsteadOfBeingDropped() async {
        let viewModel = await makeViewModel(
            httpClient: MockHTTP.xtreamClient(),
            timeout: 30,
            folder: "join"
        )

        async let first: Void = viewModel.refresh()
        async let second: Void = viewModel.refresh()
        _ = await (first, second)

        XCTAssertEqual(viewModel.state, .loaded, "A concurrent refresh must not be silently dropped")
    }

    func testSuccessfulRefreshLoadsStations() async {
        let viewModel = await makeViewModel(
            httpClient: MockHTTP.xtreamClient(),
            timeout: 30,
            folder: "success"
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.radioStations.isEmpty)
    }

    func testFreshStationResolvesCopiesSavedByOlderVersions() async {
        let viewModel = await makeViewModel(
            httpClient: MockHTTP.xtreamClient(),
            timeout: 30,
            folder: "fresh"
        )
        await viewModel.refresh()
        guard let fresh = viewModel.radioStations.first(where: { $0.name.contains("SiriusXM Hits 1") }) else {
            return XCTFail("Expected fresh station in library")
        }
        XCTAssertGreaterThanOrEqual(fresh.streamCandidates.count, 2)

        // Simulate a favorite/history entry saved by an old app version:
        // same name, but the old single URL and no alternatives.
        let stale = RadioStation(
            name: "SiriusXM Hits 1",
            streamURL: URL(string: "https://provider.example.net:8080/live/testuser/testpass/8020.m3u8")!,
            groupTitle: "SiriusXM",
            source: .xtream
        )
        XCTAssertEqual(stale.streamCandidates.count, 1)

        let resolved = viewModel.freshStation(matching: stale)
        XCTAssertEqual(resolved.id, fresh.id, "Stale copies must resolve to the fresh library station")
        XCTAssertGreaterThanOrEqual(resolved.streamCandidates.count, 2)

        // Unknown stations fall back to the given copy.
        let unknown = RadioStation(
            name: "Not In Library",
            streamURL: URL(string: "https://host.example/1.mp3")!,
            source: .xtream
        )
        XCTAssertEqual(viewModel.freshStation(matching: unknown).id, unknown.id)
    }
}
