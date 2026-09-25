import Foundation

/// A best-effort station logo lookup. Only the station name is sent to the
/// public directory; stream links can contain private tokens or credentials.
struct ManualStationLogoLookup {
    let httpClient: HTTPClient

    private struct DirectoryStation: Decodable {
        let name: String
        let favicon: String
        let url: String
        let url_resolved: String
    }

    func findLogo(name: String, streamURLs: [URL]) async -> URL? {
        var components = URLComponents(string: "https://de1.api.radio-browser.info/json/stations/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "nameExact", value: "true"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let endpoint = components.url else { return nil }
        let request = RequestBuilder.get(endpoint, timeout: 5)
        guard let (data, response) = try? await httpClient.data(for: request),
              (200..<300).contains(response.statusCode),
              data.count < 256_000,
              let candidates = try? JSONDecoder().decode([DirectoryStation].self, from: data) else {
            return nil
        }

        let exact = candidates.filter {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && validLogo($0.favicon) != nil
        }
        let streams = Set(streamURLs.map(\.absoluteString))
        if let match = exact.first(where: {
            streams.contains($0.url) || streams.contains($0.url_resolved)
        }) {
            return validLogo(match.favicon)
        }
        // A shared station name can belong to different broadcasters. Use a
        // name-only match only when the directory has one possible logo.
        let logos = Set(exact.compactMap { validLogo($0.favicon)?.absoluteString })
        guard logos.count == 1, let value = logos.first else { return nil }
        return URL(string: value)
    }

    private func validLogo(_ text: String) -> URL? {
        guard let url = ManualPlaylistResolver.validHTTPURL(text),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
