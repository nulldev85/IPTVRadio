import Foundation
import UIKit

/// Independent song lookup for manually added radio streams. iHeart publishes
/// track history; ordinary HTTP audio streams may publish ICY titles. This
/// sidecar never changes or restarts the audio being played by VLC.
struct ManualRadioNowPlayingProvider: SongInfoProviding {
    let http: HTTPClient
    private let artworkCache = ManualTrackArtworkCache()
    private let icyTitleReader: @Sendable (URL) async -> String?

    init(
        http: HTTPClient,
        icyTitleReader: @escaping @Sendable (URL) async -> String? = {
            await ICYMetadataReader().currentTitle(from: $0)
        }
    ) {
        self.http = http
        self.icyTitleReader = icyTitleReader
    }

    var sourceName: String { "radio station metadata" }
    var retriesAfterEmpty: Bool { true }

    func currentSong(for station: RadioStation) async -> SongLookup {
        guard station.source == .manual else { return .empty("not a manual station") }
        let streams: [URL]
        do {
            streams = try await ManualPlaylistResolver(httpClient: http).resolve(station.streamURL)
        } catch {
            return .empty("station playlist unavailable")
        }

        for stream in streams.prefix(3) {
            if let id = KnownManualStation.iHeartID(for: stream) {
                return await iHeartSong(id: id)
            }
            // HLS and MPEG-TS carry timed metadata in their media. VLC reads
            // that directly; opening a second audio stream cannot add ICY to
            // a manifest or a transport stream.
            if ["m3u8", "ts"].contains(stream.pathExtension.lowercased()) { continue }
            if let title = await icyTitleReader(stream) {
                let update = StreamMetadataParser.splittingCombinedTitle(
                    StreamMetadataUpdate(title: title, artist: nil, artworkData: nil)
                )
                return .found(update)
            }
        }
        return .empty("stream has no current song metadata")
    }

    private func iHeartSong(id: Int) async -> SongLookup {
        let url = URL(string: "https://us.api.iheart.com/api/v3/live-meta/stream/\(id)/trackHistory")!
        guard let (data, response) = try? await http.data(for: RequestBuilder.get(url, timeout: 8)),
              (200..<300).contains(response.statusCode),
              let history = try? JSONDecoder().decode(TrackHistory.self, from: data),
              let track = Self.currentTrack(in: history.data, now: Date()) else {
            return .empty("no current track in iHeart history")
        }

        var artwork: Data?
        if let image = track.imagePath,
           var components = URLComponents(string: image) {
            components.scheme = "https"
            if let imageURL = components.url {
                artwork = await artworkCache.image(for: imageURL.absoluteString)
                if artwork == nil,
                   let (data, response) = try? await http.data(for: RequestBuilder.get(imageURL, timeout: 8)),
                   (200..<300).contains(response.statusCode),
                   !data.isEmpty, data.count < 5_000_000,
                   UIImage(data: data) != nil {
                    artwork = data
                    await artworkCache.store(data, for: imageURL.absoluteString)
                }
            }
        }
        return .found(StreamMetadataUpdate(title: track.title, artist: track.artist, artworkData: artwork))
    }

    static func currentTrack(in tracks: [Track], now: Date) -> Track? {
        let timestamp = now.timeIntervalSince1970
        let valid = tracks.filter {
            !$0.title.isEmpty && !$0.artist.isEmpty &&
            Double($0.startTime) <= timestamp + 30
        }
        // The station history can lag the actual broadcast by a minute or
        // two. Prefer a current entry, then the newest recent entry so an
        // otherwise valid title and artwork do not disappear during that lag.
        return valid.first(where: { Double($0.endTime) >= timestamp - 15 })
            ?? valid.filter { Double($0.endTime) >= timestamp - 180 }
                .max(by: { $0.startTime < $1.startTime })
    }

    struct TrackHistory: Decodable {
        let data: [Track]
    }

    struct Track: Decodable {
        let title: String
        let artist: String
        let imagePath: String?
        let startTime: Int
        let endTime: Int
    }
}

private actor ManualTrackArtworkCache {
    private var images: [String: Data] = [:]

    func image(for key: String) -> Data? { images[key] }

    func store(_ image: Data, for key: String) {
        if images.count >= 30 { images.removeAll() }
        images[key] = image
    }
}

/// Reads a few ICY metadata blocks, then closes the connection. Some stations
/// send an empty first block during transitions; their next block has the song.
/// The actual audio continues through VLC independently.
struct ICYMetadataReader: Sendable {
    func currentTitle(from url: URL) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("Aether/1.0", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let interval = response.value(forHTTPHeaderField: "icy-metaint").flatMap(Int.init),
              (1...128_000).contains(interval) else { return nil }

        var iterator = bytes.makeAsyncIterator()
        do {
            for _ in 0..<3 {
                for _ in 0..<interval {
                    guard try await iterator.next() != nil else { return nil }
                }
                guard let length = try await iterator.next() else { return nil }
                let count = Int(length) * 16
                var block = Data()
                for _ in 0..<count {
                    guard let byte = try await iterator.next() else { return nil }
                    block.append(byte)
                }
                if let title = Self.title(from: block) { return title }
            }
            return nil
        } catch {
            return nil
        }
    }

    static func title(from block: Data) -> String? {
        guard let text = String(data: block, encoding: .utf8)
                ?? String(data: block, encoding: .windowsCP1252)
                ?? String(data: block, encoding: .isoLatin1),
              let key = text.range(of: "StreamTitle", options: .caseInsensitive) else { return nil }
        let field = text[key.upperBound...].drop(while: { $0.isWhitespace })
        guard field.first == "=" else { return nil }
        let value = field.dropFirst().drop(while: { $0.isWhitespace })
        guard let quote = value.first, quote == "'" || quote == "\"" else { return nil }
        let quoted = value.dropFirst()
        let closing = String(quote) + ";"
        guard let end = quoted.range(of: closing)?.lowerBound
                ?? quoted.lastIndex(of: quote) else { return nil }
        let title = quoted[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
