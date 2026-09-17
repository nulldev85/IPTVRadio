import Foundation

/// Downloads M3U/M3U8 playlist text from a user-supplied URL.
struct M3UClient: Sendable {
    let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault) {
        self.http = http
    }

    /// Fetches playlist text. SECURITY: the URL may embed credentials in its
    /// query string; it is never logged.
    func fetchPlaylistText(url: URL) async throws -> String {
        let request = RequestBuilder.get(url, timeout: 30)
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ProviderError.unauthorized
            }
            throw ProviderError.serverError(status: response.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ProviderError.malformedResponse("Playlist was not valid text.")
        }
        return text
    }
}
