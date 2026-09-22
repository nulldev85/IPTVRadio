import Foundation

/// Supplies current song info for a station from the provider's EPG API.
/// Radio panels commonly expose the current song there even though their
/// streams carry no metadata.
protocol ShortEPGProviding: Sendable {
    func currentSongInfo(streamID: String) async -> StreamMetadataUpdate?
}

/// Xtream implementation: reads the provider's short EPG for the stream and
/// parses the latest listing ("Artist - Title").
final class XtreamEPGProvider: ShortEPGProviding, @unchecked Sendable {
    private let credentials: CredentialsStore
    private let http: HTTPClient

    init(credentials: CredentialsStore, http: HTTPClient) {
        self.credentials = credentials
        self.http = http
    }

    func currentSongInfo(streamID: String) async -> StreamMetadataUpdate? {
        guard let stored = await credentials.load(),
              let xtream = stored.xtream,
              let client = try? XtreamClient(credentials: xtream, http: http) else { return nil }
        guard let entries = try? await client.shortEPG(streamID: streamID), !entries.isEmpty else { return nil }
        guard let entry = Self.currentEntry(in: entries) else { return nil }

        // The title is the listing. A song appears there as "Artist - Title";
        // anything else is programme information, such as a show name.
        //
        // The description is deliberately *not* searched for a song when a
        // title exists. Descriptions are prose, and prose contains dashes: a
        // blurb like "Hip-hop and R&B - hosted live from Philadelphia" splits
        // into a perfectly well-formed artist and title, which would then be
        // shown as the current track and sent to the music catalogue for album
        // art. It is only consulted when there is no title at all.
        guard let text = EPGText.decoded(entry.title) ?? EPGText.decoded(entry.description) else {
            return nil
        }

        let parsed = StreamMetadataParser.splittingCombinedTitle(
            StreamMetadataUpdate(title: text, artist: nil, artworkData: nil)
        )
        if parsed.artist != nil {
            AppLogger.playback.info("EPG listing parsed as a song")
            return parsed
        }

        // Programme information. Worth displaying, but it is not a track —
        // returning it without an artist is what keeps it out of the album-art
        // lookup, which would otherwise search for a show title.
        AppLogger.playback.info("EPG listing carries programme info only, no song")
        return StreamMetadataUpdate(title: text, artist: nil, artworkData: nil)
    }

    /// Picks the listing that is actually on air.
    ///
    /// Panels mark it with `now_playing`; otherwise the timestamps decide. The
    /// previous fallback took the *last* listing, which is the one furthest in
    /// the future: `get_short_epg` returns listings in ascending start order,
    /// so "now" sits at the front, not the back.
    static func currentEntry(in entries: [XtreamEPGEntry]) -> XtreamEPGEntry? {
        if let flagged = entries.first(where: { ($0.nowPlaying ?? 0) == 1 }) {
            return flagged
        }
        let now = Date().timeIntervalSince1970
        let covering = entries.first { entry in
            guard let start = entry.startTimestamp, let stop = entry.stopTimestamp else { return false }
            return start <= now && now < stop
        }
        return covering ?? entries.first
    }
}
