import Foundation
import AVFoundation
import UIKit

/// Song metadata extracted from the stream's timed metadata (ID3 in HLS/TS).
/// All fields optional: streams that carry no metadata simply produce nothing.
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

/// Parses timed metadata items (ID3 frames) from the player into song info.
/// Kept pure so it can be unit tested without a live stream.
enum StreamMetadataParser {
    static func parse(items: [AVMetadataItem]) -> StreamMetadataUpdate? {
        var update = StreamMetadataUpdate()

        for item in items {
            if update.title == nil, isTitle(item) {
                update.title = stringValue(of: item)
            } else if update.artist == nil, isArtist(item) {
                update.artist = stringValue(of: item)
            } else if update.artworkData == nil, isArtwork(item) {
                update.artworkData = item.dataValue ?? (item.value as? Data)
            }
        }

        let split = splittingCombinedTitle(update)
        return split.isEmpty ? nil : split
    }

    /// Splits a combined "Artist - Title" field into its two parts.
    ///
    /// Radio streams overwhelmingly carry the current song this way — in an
    /// ID3 title frame over HLS/TS, or in the ICY/Shoutcast stream title that
    /// the compatibility engine reads. Both paths need the split, because the
    /// lock screen shows artist and title separately and the artwork lookup
    /// cannot search the catalog without an artist.
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

    private static func isTitle(_ item: AVMetadataItem) -> Bool {
        if item.identifier == .id3MetadataTitleDescription { return true }
        if item.commonKey == .commonKeyTitle { return true }
        return id3Key(of: item) == "TIT2"
    }

    private static func isArtist(_ item: AVMetadataItem) -> Bool {
        if item.identifier == .id3MetadataLeadPerformer { return true }
        if item.identifier == .id3MetadataBand { return true }
        if item.commonKey == .commonKeyArtist { return true }
        return id3Key(of: item) == "TPE1"
    }

    private static func isArtwork(_ item: AVMetadataItem) -> Bool {
        if item.identifier == .id3MetadataAttachedPicture { return true }
        if item.commonKey == .commonKeyArtwork { return true }
        return id3Key(of: item) == "APIC"
    }

    private static func id3Key(of item: AVMetadataItem) -> String? {
        guard item.keySpace == .id3 else { return nil }
        return item.key as? String
    }

    private static func stringValue(of item: AVMetadataItem) -> String? {
        if let string = item.stringValue, !string.isEmpty { return string }
        if let data = item.dataValue, let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}
