import Foundation

/// What one song source found, plus a short line saying what happened when it
/// found nothing useful.
///
/// The note exists because "no song on screen" has at least five causes that
/// look identical from the outside: the channel has no EPG id, the panel's EPG
/// is empty, the EPG lists a show rather than a track, the broadcaster's
/// metadata host refused the request, or the device is offline. They need
/// different fixes, and the app is installed from CI artifacts onto a device
/// with no console attached — so the only way to tell them apart is to carry
/// the reason to the diagnostics screen.
///
/// SECURITY: a note is shown in the UI and written to the log, so it must never
/// contain a URL, a username, a password or a token. Sources put an HTTP status
/// or a channel slug in it, never an endpoint.
struct SongLookup: Sendable {
    /// What the source found, when it found something worth displaying.
    var update: StreamMetadataUpdate?
    /// Short, credential-free explanation, for diagnostics.
    var note: String?

    static func empty(_ note: String) -> SongLookup {
        SongLookup(update: nil, note: note)
    }

    static func found(_ update: StreamMetadataUpdate, note: String? = nil) -> SongLookup {
        SongLookup(update: update, note: note)
    }

    /// True when the answer names an actual track — a title *and* an artist.
    ///
    /// This is the distinction the whole song pipeline turns on. A title alone
    /// is programme information ("90s on 9 with Downtown Julie Brown"), which
    /// is worth showing but must not stop the search, and must not be sent to
    /// the album-art catalogue as if it were a song.
    var isSong: Bool {
        guard let update,
              let title = update.title, !title.isEmpty,
              let artist = update.artist, !artist.isEmpty else { return false }
        return true
    }

    /// True when there is text to display, song or not.
    ///
    /// A title is the requirement, not merely a non-empty update: an answer
    /// carrying artwork and no text would replace a visible title with nothing.
    var hasTitle: Bool {
        guard let title = update?.title else { return false }
        return !title.isEmpty
    }
}

/// A source of the currently playing song for a station, used when the stream
/// itself carries no metadata.
///
/// Sources are tried in order and the best answer wins, so they are ordered
/// most-authoritative first. A source that cannot answer returns no update
/// rather than a guess: a wrong song is worse than none, because it is also fed
/// to the album-art lookup.
protocol SongInfoProviding: Sendable {
    /// Short label for diagnostics and logs. Never contains credentials.
    var sourceName: String { get }
    /// Live radio sources may be empty during ads and must be retried later.
    var retriesAfterEmpty: Bool { get }
    func currentSong(for station: RadioStation) async -> SongLookup
}

extension SongInfoProviding {
    var retriesAfterEmpty: Bool { false }
}

/// The provider's own EPG, keyed by the station's Xtream stream id.
extension XtreamEPGProvider: SongInfoProviding {
    var sourceName: String { "provider EPG" }

    func currentSong(for station: RadioStation) async -> SongLookup {
        guard let streamID = station.xtreamStreamID, !streamID.isEmpty else {
            return .empty("channel has no EPG id")
        }
        return await currentSongInfo(streamID: streamID)
    }
}
