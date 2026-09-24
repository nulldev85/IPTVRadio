import Foundation

/// Current-song lookup for SiriusXM channels, from SiriusXM's own published
/// channel metadata.
///
/// This exists because for an IPTV panel relaying SiriusXM audio there is no
/// other source. The stream carries no ICY title, the panel's EPG lists shows
/// at best, and the audio cannot be fingerprinted on device: ShazamKit has no
/// supported way to read a live stream (Apple's own answer), works only from
/// files or the microphone, and needs an entitlement a re-signed build cannot
/// carry. What is left is the broadcaster, which publishes what is playing.
///
/// SECURITY: talks only to SiriusXM's host and sends only the station's public
/// name. Provider credentials and stream URLs are never involved, and nothing
/// URL-shaped is logged.
///
/// This is an unofficial source. It is treated accordingly: a fixed response
/// model would stop working the day the shape changes, so the JSON is walked
/// for a song, several channel slugs are attempted because the naming is not
/// documented, and a failure never disturbs playback — the caller keeps what it
/// had. Each attempt's status is reported, though: with undocumented channel
/// keys, "which key was tried and what came back" is the only way to tell a
/// wrong guess from a refused request from a channel that is between songs.
final class SiriusXMNowPlayingProvider: SongInfoProviding, @unchecked Sendable {
    private let http: HTTPClient
    private let host: String
    private let resolver: ChannelKeyResolver

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault,
         host: String = "www.siriusxm.com",
         resolver: ChannelKeyResolver = ChannelKeyResolver()) {
        self.http = http
        self.host = host
        self.resolver = resolver
    }

    var sourceName: String { "SiriusXM channel metadata" }

    func currentSong(for station: RadioStation) async -> SongLookup {
        // Resolved centrally: the listener's own key first, then the known
        // channel table, then shapes derived from the label. Derivation alone
        // produced nothing but 404s on device — the panel's label for a channel
        // simply is not the broadcaster's key for it.
        let slugs = resolver.keys(for: station)
        guard !slugs.isEmpty else {
            return .empty("station name yields no channel key")
        }

        // Each attempt's result is kept, not just the first success. With no
        // published list of channel keys the trail *is* the diagnosis: "404,
        // 404" means the names are wrong, "403" means the host refused us, and
        // "200 no song" means the key is right and the channel simply is not
        // playing a track. Those need three different fixes, and this is the
        // only place that distinction can be observed from a device.
        var trail: [String] = []
        for slug in slugs {
            guard let url = metadataURL(slug: slug) else { continue }
            let request = RequestBuilder.get(url, timeout: 8, userAgent: RequestBuilder.browserUserAgent)
            guard let (data, response) = try? await http.data(for: request) else {
                trail.append("\(slug): unreachable")
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                trail.append("\(slug): HTTP \(response.statusCode)")
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                trail.append("\(slug): not JSON")
                continue
            }
            if let song = Self.findSong(in: json) {
                AppLogger.playback.info("SiriusXM metadata matched channel slug \(slug, privacy: .public)")
                return .found(StreamMetadataUpdate(title: song.title, artist: song.artist, artworkData: nil))
            }
            trail.append("\(slug): no song in response")
        }
        return .empty(trail.isEmpty ? "no channel key could be built" : trail.joined(separator: ", "))
    }

    private func metadataURL(slug: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        // Timestamps are UTC and second-granular; the service returns the event
        // current as of the moment asked for.
        components.path = "/metadata/pdt/en-us/json/channels/\(slug)/timestamp/\(Self.timestamp())"
        return components.url
    }

    private static func timestamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
        return formatter.string(from: now)
    }

    // MARK: Channel naming

    /// Channel slugs guessed from a station name, most specific first.
    ///
    /// The fallback, not the primary path. Guessing from the label does not
    /// work in general — SiriusXM's keys are undocumented and unrelated to the
    /// label by any rule, and on device these shapes returned only 404s, which
    /// is why `SiriusXMChannelKeys` lists the known channels instead. These
    /// remain for channels the table is missing, where a guess beats nothing.
    static func candidateSlugs(for stationName: String) -> [String] {
        let cleaned = SiriusXMChannelKeys.strippingDecorations(stationName)
        guard !cleaned.isEmpty else { return [] }

        let brandless = SiriusXMChannelKeys.strippingBrand(cleaned)

        let brandlessSlug = slugify(brandless)
        var shapes: [String] = []
        // As named, then with the brand removed: SiriusXM's own keys sometimes
        // keep it ("siriusxmhits1") and sometimes do not ("shade45").
        shapes.append(slugify(cleaned))
        shapes.append(brandlessSlug)
        // A panel that drops the brand from a channel whose key keeps it: the
        // brand has to be added back, not just removed.
        if !brandlessSlug.isEmpty {
            shapes.append("siriusxm" + brandlessSlug)
        }
        // Leading article dropped, both ways — "The Highway" is keyed both as
        // "thehighway" and as "highway" across SiriusXM's own surfaces.
        let articleless = slugify(Self.strippingLeadingArticle(brandless))
        if articleless != brandlessSlug, !articleless.isEmpty {
            shapes.append(articleless)
            shapes.append("siriusxm" + articleless)
        }

        var slugs: [String] = []
        for slug in shapes where !slug.isEmpty && slug != "siriusxm" {
            if !slugs.contains(slug) { slugs.append(slug) }
        }
        // Bounded: this runs every poll, and an unbounded list would mean a
        // burst of requests every thirty seconds for a channel that will never
        // match anyway.
        return Array(slugs.prefix(5))
    }

    private static func strippingLeadingArticle(_ text: String) -> String {
        let lowered = text.lowercased()
        for article in ["the ", "a "] where lowered.hasPrefix(article) {
            return String(text.dropFirst(article.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
    }

    // MARK: Response walking

    /// Finds a song anywhere in the response.
    ///
    /// A title and an artist are required *together*, from the same object.
    /// That is the whole safeguard: a lone string in this response is as likely
    /// to be the channel or the show, and both have already been mistaken for
    /// songs here — once on screen, and once badly enough to switch off the
    /// EPG. Requiring the pair is also exactly what the album-art lookup needs.
    static func findSong(in json: Any) -> (title: String, artist: String)? {
        if let object = json as? [String: Any] {
            if let song = songPair(in: object) { return song }
            for value in object.values {
                if let song = findSong(in: value) { return song }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let song = findSong(in: value) { return song }
            }
        }
        return nil
    }

    private static let titleKeys = ["songname", "song", "title", "name", "tracktitle"]
    private static let artistKeys = ["artistname", "artist", "artists", "performer", "albumartist"]

    private static func songPair(in object: [String: Any]) -> (title: String, artist: String)? {
        guard let title = firstString(in: object, matching: titleKeys),
              let artist = firstString(in: object, matching: artistKeys) else { return nil }
        return (title, artist)
    }

    /// First non-empty string reachable under any of `keys`, looking one level
    /// into a nested object or array so `artists: [{ name: ... }]` resolves.
    private static func firstString(in object: [String: Any], matching keys: [String]) -> String? {
        for (rawKey, value) in object {
            guard keys.contains(rawKey.lowercased()) else { continue }
            if let text = nonEmpty(value as? String) { return text }
            if let nested = value as? [String: Any],
               let text = nonEmpty(nested["name"] as? String) ?? nonEmpty(nested["title"] as? String) {
                return text
            }
            if let array = value as? [Any] {
                for element in array {
                    if let text = nonEmpty(element as? String) { return text }
                    if let nested = element as? [String: Any],
                       let text = nonEmpty(nested["name"] as? String) ?? nonEmpty(nested["title"] as? String) {
                        return text
                    }
                }
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
