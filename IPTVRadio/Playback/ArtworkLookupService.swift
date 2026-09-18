import Foundation

/// Looks up song artwork from Apple's public catalog (iTunes Search API) for
/// radio streams that carry only text metadata (artist/title) and no embedded
/// album art. Uses no credentials and no tracking.
struct ArtworkLookupService {
    let http: HTTPClient
    private let cache = ArtworkLookupCache()

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault) {
        self.http = http
    }

    /// Resolves and downloads artwork for a song. Returns image data or nil.
    func artworkData(artist: String, title: String) async -> Data? {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 3 else { return nil }

        if let cached = cache.entry(for: term) {
            switch cached {
            case .artwork(let data): return data
            case .notFound: return nil
            }
        }

        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let searchURL = components.url else { return nil }

        do {
            let (data, response) = try await http.data(for: RequestBuilder.get(searchURL, timeout: 8))
            guard (200..<300).contains(response.statusCode) else {
                cache.store(.notFound, for: term)
                return nil
            }
            let results = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let artworkString = results.results.first?.artworkUrl100,
                  let artworkURL = URL(string: artworkString.replacingOccurrences(of: "100x100", with: "600x600")) else {
                cache.store(.notFound, for: term)
                return nil
            }
            let (imageData, imageResponse) = try await http.data(for: RequestBuilder.get(artworkURL, timeout: 8))
            guard (200..<300).contains(imageResponse.statusCode), !imageData.isEmpty else {
                cache.store(.notFound, for: term)
                return nil
            }
            cache.store(.artwork(imageData), for: term)
            return imageData
        } catch {
            cache.store(.notFound, for: term)
            return nil
        }
    }
}

private struct ITunesSearchResponse: Decodable {
    struct Result: Decodable {
        var artworkUrl100: String?
    }

    var results: [Result]
}

/// Session-lifetime cache. Misses are cached too, so a song with no catalog
/// match is not looked up again on every metadata refresh.
private final class ArtworkLookupCache {
    enum Entry {
        case artwork(Data)
        case notFound
    }

    private let lock = NSLock()
    private var storage: [String: Entry] = [:]

    func entry(for term: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return storage[term]
    }

    func store(_ entry: Entry, for term: String) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count > 200 { storage.removeAll() }
        storage[term] = entry
    }
}
