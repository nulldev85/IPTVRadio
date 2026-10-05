import Foundation

struct DialQuery: Sendable {
    var place: String
    var genre: String?
    var name: String
    var worldwide: Bool
    var homeCountryCode: String
}

struct DialStation: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Original directory link, usually stable across CDN redirects.
    let streamURL: URL
    /// Resolved direct stream for a quick listening preview.
    let previewURL: URL
    let logoURL: URL?
    let location: String
    let tags: [String]
    let codec: String?
    let bitrate: Int?

    func previewStation(playbackURLs: [URL]) -> RadioStation {
        let first = playbackURLs.first ?? previewURL
        var alternatives = Array(playbackURLs.dropFirst())
        if streamURL != first { alternatives.append(streamURL) }
        return RadioStation(
            id: "dial-\(id)",
            name: name,
            streamURL: first,
            groupTitle: location.isEmpty ? "Aether Dial" : location,
            logoURL: logoURL,
            source: .manual,
            alternativeStreamURLs: alternatives,
            directoryStationID: id
        )
    }
}

enum AetherDialError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "The radio directory is unavailable. Try again in a moment."
        case .invalidResponse: "The radio directory returned an unreadable list. Try again later."
        }
    }
}

/// Reads Radio Browser's public station directory. No account, provider URL,
/// credentials, listening history, or precise location is sent to the service.
struct AetherDialService: Sendable {
    let httpClient: HTTPClient

    private static let mirrors = [
        URL(string: "https://de1.api.radio-browser.info")!,
        URL(string: "https://nl1.api.radio-browser.info")!
    ]
    private static let userAgent = "Aether/1.0 (iOS; github.com/nulldev85/IPTVRadio)"

    func search(_ query: DialQuery) async throws -> [DialStation] {
        let place = String(query.place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let filters: [[URLQueryItem]]
        if query.worldwide && place.isEmpty {
            filters = [[]]
        } else if place.isEmpty {
            filters = [[URLQueryItem(name: "countrycode", value: query.homeCountryCode)]]
        } else if place.count == 2, place.allSatisfy({ $0.isLetter }) {
            filters = [[URLQueryItem(name: "countrycode", value: place.uppercased())]]
        } else {
            // The directory indexes countries and states separately. Search
            // both because a listener may type either one into the place field.
            filters = [
                [URLQueryItem(name: "state", value: place)],
                [URLQueryItem(name: "country", value: place)]
            ]
        }

        if filters.count == 1 {
            return try await fetch(query, placeItems: filters[0])
        }
        async let stateResult = fetch(query, placeItems: filters[0])
        async let countryResult = fetch(query, placeItems: filters[1])
        let byState = try? await stateResult
        let byCountry = try? await countryResult
        guard byState != nil || byCountry != nil else { throw AetherDialError.unavailable }
        var seen = Set<String>()
        let combined = ((byState ?? []) + (byCountry ?? []))
            .filter { seen.insert($0.id).inserted }
        if combined.isEmpty && !place.isEmpty && query.name.isEmpty {
            // City names are not a directory field, but they sometimes appear
            // in station names. Offer those matches when place search is empty.
            var cityQuery = query
            cityQuery.name = place
            return try await fetch(cityQuery, placeItems: [])
        }
        return combined
    }

    /// The directory asks clients to register a click on playback. This is
    /// best-effort and never delays or interrupts the listener's stream.
    func registerClick(stationID: String) async {
        guard UUID(uuidString: stationID) != nil else { return }
        let endpoint = Self.mirrors[0]
            .appendingPathComponent("json")
            .appendingPathComponent("url")
            .appendingPathComponent(stationID)
        let request = RequestBuilder.get(endpoint, timeout: 4, userAgent: Self.userAgent)
        _ = try? await httpClient.data(for: request)
    }

    private func fetch(_ query: DialQuery, placeItems: [URLQueryItem]) async throws -> [DialStation] {
        var items = placeItems + [
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: "60")
        ]
        let name = String(query.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
        if let genre = query.genre, !genre.isEmpty {
            items.append(URLQueryItem(name: "tag", value: genre))
        }

        var receivedMalformedResponse = false
        for mirror in Self.mirrors {
            let path = mirror.appendingPathComponent("json")
                .appendingPathComponent("stations")
                .appendingPathComponent("search")
            var endpoint = URLComponents(url: path, resolvingAgainstBaseURL: false)!
            endpoint.queryItems = items
            guard let url = endpoint.url else { continue }
            let request = RequestBuilder.get(url, timeout: 10, userAgent: Self.userAgent)
            guard let (data, response) = try? await httpClient.data(for: request),
                  (200..<300).contains(response.statusCode) else { continue }
            guard data.count < 1_000_000,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let rows = object as? [[String: Any]] else {
                receivedMalformedResponse = true
                continue
            }
            var seen = Set<String>()
            return rows.compactMap { Self.station(from: $0) }
                .filter { seen.insert($0.id).inserted }
        }
        if receivedMalformedResponse { throw AetherDialError.invalidResponse }
        throw AetherDialError.unavailable
    }

    private static func station(from row: [String: Any]) -> DialStation? {
        guard let id = row["stationuuid"] as? String,
              UUID(uuidString: id) != nil,
              let rawName = row["name"] as? String else { return nil }
        let name = String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty, number(row["lastcheckok"]) == 1 else { return nil }

        let resolved = safeURL((row["url_resolved"] as? String) ?? "")
        let original = safeURL((row["url"] as? String) ?? "")
        guard let streamURL = original ?? resolved else { return nil }

        let favicon = (row["favicon"] as? String) ?? ""
        let logoURL = safeURL(favicon).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        let state = ((row["state"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let country = ((row["country"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = [state, country].filter { !$0.isEmpty }.joined(separator: " · ")
        let tags = ((row["tags"] as? String) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let codec = ((row["codec"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bitrate = number(row["bitrate"])
        return DialStation(
            id: id,
            name: name,
            streamURL: streamURL,
            previewURL: resolved ?? streamURL,
            logoURL: logoURL,
            location: location,
            tags: tags,
            codec: codec.isEmpty ? nil : codec,
            bitrate: (bitrate ?? 0) > 0 ? bitrate : nil
        )
    }

    private static func safeURL(_ text: String) -> URL? {
        guard let url = ManualPlaylistResolver.validHTTPURL(text),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
