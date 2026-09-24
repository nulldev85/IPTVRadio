import Foundation

/// Current-song lookup from a public SiriusXM playlist tracker.
///
/// A second, independent source for the same question the broadcaster's own
/// endpoint answers. It exists because one unverifiable endpoint is a single
/// point of failure: the broadcaster's metadata path is undocumented and could
/// be moved, geo-restricted or refused outright, and when that happens there is
/// no song at all. Two sources that fail differently are far more likely to
/// yield one that works, and the diagnostics screen reports each separately so
/// it is visible which one did.
///
/// SECURITY: sends only a channel key derived from the station's public name.
/// Provider credentials and stream URLs are never involved.
///
/// Unofficial, and treated like the other one: the response is walked for a
/// title and artist appearing together rather than decoded into a fixed model,
/// so a reshuffle degrades to "no song" instead of breaking, and every attempt
/// reports its HTTP status.
final class XMPlaylistNowPlayingProvider: SongInfoProviding, @unchecked Sendable {
    private let http: HTTPClient
    private let host: String
    private let resolver: ChannelKeyResolver

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault,
         host: String = "xmplaylist.com",
         resolver: ChannelKeyResolver = ChannelKeyResolver()) {
        self.http = http
        self.host = host
        self.resolver = resolver
    }

    var sourceName: String { "SiriusXM playlist tracker" }

    func currentSong(for station: RadioStation) async -> SongLookup {
        let keys = resolver.keys(for: station)
        guard !keys.isEmpty else { return .empty("no channel key for this station") }

        var trail: [String] = []
        // True once a key has been answered with usable JSON, song or not.
        var reached = false
        for key in keys {
            guard let url = endpoint(key: key) else { continue }
            let request = RequestBuilder.liveGet(url, timeout: 8, userAgent: RequestBuilder.browserUserAgent)
            guard let (data, response) = try? await http.data(for: request) else {
                trail.append("\(key): unreachable")
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                trail.append("\(key): HTTP \(response.statusCode)")
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                trail.append("\(key): not JSON")
                continue
            }
            // The response is a list of recent plays. Which end of it is
            // current is not documented, so the walk takes the newest
            // *timestamped* play rather than the first one it reaches — see
            // `findSong`. Reading the wrong end shows a real song that never
            // changes, which is the failure this whole path had.
            if let song = SiriusXMNowPlayingProvider.findSong(in: json) {
                AppLogger.playback.info("Playlist tracker matched channel \(key, privacy: .public)")
                return .found(
                    StreamMetadataUpdate(title: song.title, artist: song.artist, artworkData: nil),
                    note: SiriusXMNowPlayingProvider.matchedNote(key: key, play: song)
                )
            }
            reached = true
            trail.append("\(key): no song in response")
        }
        guard !trail.isEmpty else { return .empty("no channel key could be built") }
        // Reached and understood, but between songs: the caller must keep asking.
        return reached ? .silent(trail.joined(separator: ", ")) : .empty(trail.joined(separator: ", "))
    }

    private func endpoint(key: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/station/\(key)"
        return components.url
    }
}
