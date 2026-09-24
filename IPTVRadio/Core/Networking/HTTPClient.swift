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
    /// Default identity for provider APIs.
    static let defaultUserAgent = "IPTVRadio/1.0 (iOS)"

    /// Identity for public web endpoints that serve JSON to browsers.
    ///
    /// Some of them sit behind a CDN that answers a bare tool user-agent with a
    /// challenge page or a 403, so a request that is honest about being a tool
    /// gets nothing. This is a plain browser identity for public, unauthenticated
    /// resources — nothing here bypasses authentication or access control.
    static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// `cachePolicy` matters for the song lookups: they ask "what is playing
    /// right now", and the default policy lets `URLSession` answer a repeat
    /// request from `URLCache` for as long as the server's headers allow. That
    /// is a frozen song title — the same body returned every thirty seconds
    /// while the audio moves on — so those callers pass
    /// `.reloadIgnoringLocalCacheData`.
    static func get(
        _ url: URL,
        timeout: TimeInterval = 20,
        userAgent: String = RequestBuilder.defaultUserAgent,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = cachePolicy
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A GET for data that changes minute to minute and must never be served
    /// from the local cache.
    static func liveGet(
        _ url: URL,
        timeout: TimeInterval = 20,
        userAgent: String = RequestBuilder.defaultUserAgent
    ) -> URLRequest {
        get(url, timeout: timeout, userAgent: userAgent, cachePolicy: .reloadIgnoringLocalCacheData)
    }
}
