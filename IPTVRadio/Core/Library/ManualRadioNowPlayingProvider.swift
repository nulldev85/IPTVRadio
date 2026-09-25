import Foundation

/// Live track details for the local stations identified by their stream URLs.
/// iHeart publishes a track history; the other two send ICY song titles in
/// their audio responses. This backs up VLC's own metadata notifications.
struct ManualRadioNowPlayingProvider: SongInfoProviding {
    let http: HTTPClient
    private let artworkCache = ManualTrackArtworkCache()

    init(http: HTTPClient) {
        self.http = http
    }

    var sourceName: String { "radio station metadata" }
    var retriesAfterEmpty: Bool { true }

    func currentSong(for station: RadioStation) async -> SongLookup {
        guard station.source == .manual else { return .empty("not a manual station") }
        if let id = KnownManualStation.iHeartID(for: station.streamURL) {
            return await iHeartSong(id: id)
        }
        if KnownManualStation.hasICYMetadata(for: station.streamURL),
           let title = await ICYMetadataReader().currentTitle(from: station.streamURL) {
            let update = StreamMetadataParser.splittingCombinedTitle(
                StreamMetadataUpdate(title: title, artist: nil, artworkData: nil)
            )
            return .found(update)
        }
        return .empty("no current ICY song title")
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
                   !data.isEmpty, data.count < 5_000_000 {
                    artwork = data
                    await artworkCache.store(data, for: imageURL.absoluteString)
                }
            }
        }
        return .found(StreamMetadataUpdate(title: track.title, artist: track.artist, artworkData: artwork))
    }

    static func currentTrack(in tracks: [Track], now: Date) -> Track? {
        let timestamp = now.timeIntervalSince1970
        return tracks.first {
            !$0.title.isEmpty && !$0.artist.isEmpty &&
            Double($0.startTime) <= timestamp + 30 &&
            Double($0.endTime) >= timestamp - 15
        }
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

/// Reads only the first ICY metadata block, then closes the connection. The
/// actual audio continues through VLC; this brief second request supplies a
/// current title when VLCKit does not publish it to the app.
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
        guard let (bytes, response) = try? await session.bytes(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let interval = response.value(forHTTPHeaderField: "icy-metaint").flatMap(Int.init),
              (1...1_000_000).contains(interval) else { return nil }

        var iterator = bytes.makeAsyncIterator()
        do {
            for _ in 0..<interval {
                guard try await iterator.next() != nil else { return nil }
            }
            guard let length = try await iterator.next() else { return nil }
            let count = Int(length) * 16
            guard count > 0 else { return nil }
            var block = Data()
            for _ in 0..<count {
                guard let byte = try await iterator.next() else { return nil }
                block.append(byte)
            }
            return Self.title(from: block)
        } catch {
            return nil
        }
    }

    static func title(from block: Data) -> String? {
        guard let text = String(data: block, encoding: .utf8) ?? String(data: block, encoding: .isoLatin1),
              let start = text.range(of: "StreamTitle='") else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: "';") else { return nil }
        let title = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
