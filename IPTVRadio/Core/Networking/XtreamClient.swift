import Foundation

/// Client for the Xtream Codes API exposed by the user's own provider.
///
/// SECURITY: This client intentionally has no logging of request URLs because
/// Xtream requests carry the username and password as query parameters.
struct XtreamClient: Sendable {
    let credentials: XtreamCredentials
    let http: HTTPClient
    let baseURL: URL

    init(credentials: XtreamCredentials, http: HTTPClient) throws {
        guard let base = credentials.normalizedBaseURL else {
            throw ProviderError.invalidServerURL
        }
        self.credentials = credentials
        self.http = http
        // If the user typed no scheme we defaulted to HTTPS; if they typed an
        // explicit http:// we honor it but the UI shows a warning.
        self.baseURL = base
    }

    var isSecure: Bool { baseURL.scheme?.lowercased() == "https" }

    // MARK: Endpoint URLs (never logged)

    func authURL() -> URL {
        baseURL
            .appendingPathComponent("player_api.php")
            .appending(
                queryItems: [
                    URLQueryItem(name: "username", value: credentials.username),
                    URLQueryItem(name: "password", value: credentials.password),
                ]
            )
    }

    func categoriesURL() -> URL {
        baseURL
            .appendingPathComponent("player_api.php")
            .appending(
                queryItems: [
                    URLQueryItem(name: "username", value: credentials.username),
                    URLQueryItem(name: "password", value: credentials.password),
                    URLQueryItem(name: "action", value: "get_live_categories"),
                ]
            )
    }

    func liveStreamsURL() -> URL {
        baseURL
            .appendingPathComponent("player_api.php")
            .appending(
                queryItems: [
                    URLQueryItem(name: "username", value: credentials.username),
                    URLQueryItem(name: "password", value: credentials.password),
                    URLQueryItem(name: "action", value: "get_live_streams"),
                ]
            )
    }

    func shortEPGURL(streamID: String) -> URL {
        baseURL
            .appendingPathComponent("player_api.php")
            .appending(
                queryItems: [
                    URLQueryItem(name: "username", value: credentials.username),
                    URLQueryItem(name: "password", value: credentials.password),
                    URLQueryItem(name: "action", value: "get_short_epg"),
                    URLQueryItem(name: "stream_id", value: streamID),
                ]
            )
    }

    /// HLS manifest URL for a live stream id.
    func streamURL(streamID: String, format: String = "m3u8") -> URL {
        baseURL
            .appendingPathComponent("live")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(streamID).\(format)")
    }

    // MARK: API calls

    func authenticate() async throws -> SessionInfo {
        let (data, response) = try await perform(authURL())
        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPStatus(response.statusCode)
        }
        let decoded = try XtreamDecoder.decodeAuth(data)
        let session = SessionInfo(authResponse: decoded, fallbackBase: baseURL)
        guard session.isAuthenticated else {
            throw ProviderError.unauthorized
        }
        return session
    }

    func categories() async throws -> [XtreamLiveCategory] {
        let (data, response) = try await perform(categoriesURL())
        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPStatus(response.statusCode)
        }
        return try XtreamDecoder.decodeCategories(data)
    }

    func liveStreams() async throws -> [XtreamLiveStream] {
        let (data, response) = try await perform(liveStreamsURL())
        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPStatus(response.statusCode)
        }
        return try XtreamDecoder.decodeLiveStreams(data)
    }

    /// Short EPG listings for a live stream. Radio panels commonly expose the
    /// current song here ("Artist - Title"), which the app surfaces as song
    /// info when the stream itself carries no metadata.
    func shortEPG(streamID: String) async throws -> [XtreamEPGEntry] {
        let (data, response) = try await perform(shortEPGURL(streamID: streamID))
        guard (200..<300).contains(response.statusCode) else {
            throw mapHTTPStatus(response.statusCode)
        }
        return try XtreamDecoder.decodeShortEPG(data)
    }

    // MARK: Internals

    private func perform(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let request = RequestBuilder.get(url)
        do {
            return try await http.data(for: request)
        } catch let error as ProviderError {
            throw error
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch URLError.cancelled {
            throw ProviderError.cancelled
        } catch URLError.timedOut {
            throw ProviderError.timedOut
        } catch URLError.notConnectedToInternet, URLError.networkConnectionLost, URLError.cannotFindHost, URLError.cannotConnectToHost, URLError.dnsLookupFailed {
            throw ProviderError.networkUnreachable
        } catch {
            throw ProviderError.networkUnreachable
        }
    }

    private func mapHTTPStatus(_ status: Int) -> ProviderError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 408, 429:
            return .timedOut
        default:
            return .serverError(status: status)
        }
    }
}

extension URL {
    /// Appends query items, preserving existing ones.
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        let existing = components.queryItems ?? []
        components.queryItems = existing + queryItems
        return components.url ?? self
    }
}
