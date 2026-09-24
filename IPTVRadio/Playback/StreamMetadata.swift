import Foundation
import UIKit

/// Song metadata for the current track, from whichever source supplied it: the
/// stream's own ICY title, the provider's EPG, or a broadcaster lookup. All
/// fields optional — a stream that carries no metadata simply produces nothing.
struct StreamMetadataUpdate: Equatable, Sendable {
    var title: String?
    var artist: String?
    var artworkData: Data?

    var isEmpty: Bool {
        (title?.isEmpty ?? true) && (artist?.isEmpty ?? true) && artworkData == nil
    }
}

/// UI-facing now-playing metadata: song title/artist/artwork for the current
/// stream. `artworkImage` is decoded once when the metadata is built.
struct NowPlayingMetadata: Equatable {
    var title: String?
    var artist: String?
    var artworkData: Data?
    private(set) var artworkImage: UIImage?

    init(title: String?, artist: String?, artworkData: Data?) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.artworkImage = artworkData.flatMap { UIImage(data: $0) }
    }

    static func == (lhs: NowPlayingMetadata, rhs: NowPlayingMetadata) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.artworkData == rhs.artworkData
    }
}

/// Turns the text a stream carries into song info. Kept pure so it can be unit
/// tested without a live stream.
enum StreamMetadataParser {
    /// Splits a combined "Artist - Title" field into its two parts.
    ///
    /// Radio streams overwhelmingly carry the current song this way, and so do
    /// the out-of-stream sources: the ICY/Shoutcast stream title the engine
    /// reads, and the provider's EPG listing. Every path needs the split,
    /// because the lock screen shows artist and title separately and the
    /// artwork lookup cannot search the catalog without an artist.
    static func splittingCombinedTitle(_ update: StreamMetadataUpdate) -> StreamMetadataUpdate {
        var update = update
        guard update.artist == nil, let title = update.title,
              let separator = title.range(of: " - ") else { return update }
        let artist = String(title[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        let song = String(title[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !song.isEmpty else { return update }
        update.artist = artist
        update.title = song
        return update
    }
}
