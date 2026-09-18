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

        // The latest listing normally covers "now".
        guard let entry = entries.last else { return nil }
        let text = EPGText.decoded(entry.title)
            ?? EPGText.decoded(entry.description)
        guard let text, !text.isEmpty else { return nil }

        if let separator = text.range(of: " - ") {
            let artist = String(text[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(text[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return StreamMetadataUpdate(title: title, artist: artist, artworkData: nil)
            }
        }
        return StreamMetadataUpdate(title: text, artist: nil, artworkData: nil)
    }
}
