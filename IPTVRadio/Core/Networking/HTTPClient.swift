import Foundation

/// Abstraction over the network transport so tests can inject mocked responses.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed client with configurable timeouts.
struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A client tuned for provider APIs: modest request timeout, generous
    /// resource timeout for large playlists.
    static var providerDefault: URLSessionHTTPClient {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        return URLSessionHTTPClient(session: URLSession(configuration: config))
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("Non-HTTP response")
        }
        return (data, http)
    }
}

/// Builds requests. SECURITY: never logs the resulting URLs (they embed
/// credentials in Xtream deployments).
enum RequestBuilder {
    static func get(_ url: URL, timeout: TimeInterval = 20) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("IPTVRadio/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
