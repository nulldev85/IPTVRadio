import Foundation

/// A source of the currently playing song for a station, used when the stream
/// itself carries no metadata.
///
/// Sources are tried in order and the first answer wins, so they are ordered
/// most-authoritative first. A source that cannot answer returns nil rather
/// than a guess: a wrong song is worse than none, because it is also fed to the
/// album-art lookup.
protocol SongInfoProviding: Sendable {
    /// Short label for diagnostics and logs. Never contains credentials.
    var sourceName: String { get }
    func currentSong(for station: RadioStation) async -> StreamMetadataUpdate?
}

/// The provider's own EPG, keyed by the station's Xtream stream id.
extension XtreamEPGProvider: SongInfoProviding {
    var sourceName: String { "provider EPG" }

    func currentSong(for station: RadioStation) async -> StreamMetadataUpdate? {
        guard let streamID = station.xtreamStreamID, !streamID.isEmpty else { return nil }
        return await currentSongInfo(streamID: streamID)
    }
}
