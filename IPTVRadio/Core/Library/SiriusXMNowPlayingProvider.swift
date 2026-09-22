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
/// documented, and any failure is simply nil — the caller keeps what it had.
final class SiriusXMNowPlayingProvider: SongInfoProviding, @unchecked Sendable {
    private let http: HTTPClient
    private let host: String

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault,
         host: String = "www.siriusxm.com") {
        self.http = http
        self.host = host
    }

    var sourceName: String { "SiriusXM channel metadata" }

    func currentSong(for station: RadioStation) async -> StreamMetadataUpdate? {
        let slugs = Self.candidateSlugs(for: station.name)
        guard !slugs.isEmpty else { return nil }

        for slug in slugs {
            guard let url = metadataURL(slug: slug) else { continue }
            guard let (data, response) = try? await http.data(for: RequestBuilder.get(url, timeout: 8)),
                  (200..<300).contains(response.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let song = Self.findSong(in: json) {
                AppLogger.playback.info("SiriusXM metadata matched channel slug \(slug, privacy: .public)")
                return StreamMetadataUpdate(title: song.title, artist: song.artist, artworkData: nil)
            }
        }
        return nil
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

    /// Channel slugs to try for a station name, most specific first.
    ///
    /// Panels label the same channel many ways ("Radio: SiriusXM FLY", "SXM
    /// Fly", "Fly"), and SiriusXM's own slugs are undocumented — some keep the
    /// brand ("siriusxmhits1"), others drop it ("shade45"). Rather than guess
    /// one rule, a few shapes are tried and the first that answers wins.
    static func candidateSlugs(for stationName: String) -> [String] {
        let cleaned = stationName
            .replacingOccurrences(of: "Radio:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "Radio -", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        let withBrand = slugify(cleaned)
        let withoutBrand = slugify(
            cleaned
                .replacingOccurrences(of: "SiriusXM", with: " ", options: .caseInsensitive)
                .replacingOccurrences(of: "SXM", with: " ", options: .caseInsensitive)
        )

        var slugs: [String] = []
        for slug in [withBrand, withoutBrand] where !slug.isEmpty {
            if !slugs.contains(slug) { slugs.append(slug) }
        }
        return slugs
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
