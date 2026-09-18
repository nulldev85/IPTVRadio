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
}
