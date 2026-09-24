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
        // True once a key has been answered with usable JSON, song or not.
        var reached = false
        for slug in slugs {
            guard let url = metadataURL(slug: slug) else { continue }
            let request = RequestBuilder.liveGet(url, timeout: 8, userAgent: RequestBuilder.browserUserAgent)
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
                return .found(
                    StreamMetadataUpdate(title: song.title, artist: song.artist, artworkData: nil),
                    note: Self.matchedNote(key: slug, play: song)
                )
            }
            reached = true
            trail.append("\(slug): no song in response")
        }
        guard !trail.isEmpty else { return .empty("no channel key could be built") }
        // Reached and understood, but between songs: the caller must keep asking.
        return reached ? .silent(trail.joined(separator: ", ")) : .empty(trail.joined(separator: ", "))
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

    /// One play found in a response: the track, and when it was played if the
    /// response said so.
    struct Play {
        let title: String
        let artist: String
        let playedAt: Date?
    }

    /// Finds the song that is playing *now* in a response.
    ///
    /// Both sources answer with recent plays rather than a bare "now", and
    /// neither documents the order. Taking the first title/artist pair the walk
    /// reaches therefore risks reporting a fixed, hours-old play — a real song
    /// with real album art that never changes however long the station runs,
    /// which is indistinguishable from working until you listen for a while.
    /// No assumption about ordering can rule that out, and an undocumented
    /// source can reorder its response without notice.
    ///
    /// So every play in the response is collected with the timestamp nearest
    /// it, and the newest one wins; order stops mattering. When nothing in the
    /// response is timestamped there is nothing else to go on, and the first
    /// play found is used.
    static func findSong(in json: Any) -> Play? {
        var plays: [Play] = []
        collectPlays(in: json, inheriting: nil, into: &plays)
        guard !plays.isEmpty else { return nil }
        let newest = plays
            .filter { $0.playedAt != nil }
            .max { ($0.playedAt ?? .distantPast) < ($1.playedAt ?? .distantPast) }
        return newest ?? plays.first
    }

    /// Walks the response, carrying the closest enclosing timestamp down with
    /// it: the play time sits *beside* the track as often as inside it
    /// (`{ timestamp: …, track: { … } }`).
    private static func collectPlays(in json: Any, inheriting inherited: Date?, into plays: inout [Play]) {
        if let object = json as? [String: Any] {
            let stamp = playTime(in: object) ?? inherited
            if let pair = songPair(in: object) {
                plays.append(Play(title: pair.title, artist: pair.artist, playedAt: stamp))
                // No deeper: what is nested inside a matched object is the same
                // play's album or channel, not another play.
                return
            }
            // Sorted, so a response always walks the same way — dictionary
            // iteration order is not stable between runs.
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                collectPlays(in: value, inheriting: stamp, into: &plays)
            }
            return
        }
        if let array = json as? [Any] {
            for value in array {
                collectPlays(in: value, inheriting: inherited, into: &plays)
            }
        }
    }

    private static let titleKeys = ["songname", "song", "title", "name", "tracktitle"]
    private static let artistKeys = ["artistname", "artist", "artists", "performer", "albumartist"]
    /// Spelled without separators: keys are normalised before matching, so this
    /// covers `start_time`, `startTime` and `start-time` alike.
    private static let timeKeys = [
        "timestamp", "starttime", "startdatetime", "startdate", "airedat", "airtime",
        "playedat", "playedon", "datetime", "date", "time", "start", "lastplayed"
    ]

    private static func songPair(in object: [String: Any]) -> (title: String, artist: String)? {
        guard let title = firstString(in: object, matching: titleKeys),
              let artist = firstString(in: object, matching: artistKeys) else { return nil }
        return (title, artist)
    }

    /// When this object says it was played. Anything that does not parse as a
    /// date is ignored, which is what makes broad keys like `date` safe here.
    private static func playTime(in object: [String: Any]) -> Date? {
        for key in object.keys.sorted() {
            guard timeKeys.contains(normalisedKey(key)), let value = object[key] else { continue }
            if let date = date(from: value) { return date }
        }
        return nil
    }

    /// Same folding the channel slugs use: lowercased, separators dropped.
    private static func normalisedKey(_ key: String) -> String { slugify(key) }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// The broadcaster's own spelling, the one its metadata path uses in its URLs.
    private static let broadcasterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HH:mm:ss"
        return formatter
    }()

    private static func date(from value: Any) -> Date? {
        if let text = value as? String { return date(fromText: text) }
        if let number = value as? NSNumber { return date(fromEpoch: number.doubleValue) }
        return nil
    }

    private static func date(fromText text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = isoFractionalFormatter.date(from: trimmed) { return date }
        if let date = isoFormatter.date(from: trimmed) { return date }
        if let seconds = Double(trimmed) { return date(fromEpoch: seconds) }
        return broadcasterFormatter.date(from: trimmed)
    }

    private static func date(fromEpoch value: Double) -> Date? {
        // Seconds and milliseconds are both used in the wild. A value past the
        // year 5000 in seconds is milliseconds; one before 2001 is not a
        // timestamp at all (a flag, a count, an id).
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        guard seconds > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
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

    // MARK: Reporting

    /// The note a matched lookup reports, e.g. `fly: matched, play from 03:04:11
    /// (12s ago)`.
    ///
    /// The age is the point. A song that has stopped updating looks exactly like
    /// one that is up to date on the diagnostics screen, and this is what tells
    /// the two apart from a screenshot: a play that keeps getting older while
    /// the audio moves on says the source is stale, not that the app stopped
    /// asking it.
    ///
    /// SECURITY: channel key and clock time only, never an endpoint.
    static func matchedNote(key: String, play: Play, now: Date = Date()) -> String {
        guard let playedAt = play.playedAt else { return "\(key): matched" }
        return "\(key): matched, play from \(timeFormatter.string(from: playedAt)) (\(age(of: playedAt, now: now)))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 90 { return "\(Int(seconds))s ago" }
        if seconds < 5400 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
