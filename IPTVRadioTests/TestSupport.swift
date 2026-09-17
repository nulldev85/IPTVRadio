import XCTest
@testable import IPTVRadio

/// URLProtocol-based mock so network-dependent code is fully testable.
final class MockURLProtocol: URLProtocol {
    /// Handler keyed by a discriminator extracted from the request. Tests set
    /// this before creating the session; it routes by query content.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mock.local")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum MockHTTP {
    /// Builds an HTTPClient backed by MockURLProtocol.
    static func client(handler: @escaping (URLRequest) throws -> (Int, Data)) -> HTTPClient {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: config))
    }

    /// Routes Xtream requests (auth/categories/streams) to fixture data.
    static func xtreamClient(
        auth: String = Fixtures.authResponseJSON,
        categories: String = Fixtures.categoriesJSON,
        streams: String = Fixtures.liveStreamsJSON
    ) -> HTTPClient {
        client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("get_live_categories") {
                return (200, Data(categories.utf8))
            }
            if url.contains("get_live_streams") {
                return (200, Data(streams.utf8))
            }
            if url.contains("player_api.php") {
                return (200, Data(auth.utf8))
            }
            return (404, Data("{}".utf8))
        }
    }
}

extension XCTestCase {
    /// Standard in-memory defaults to isolate SettingsStore between tests.
    func makeIsolatedDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
