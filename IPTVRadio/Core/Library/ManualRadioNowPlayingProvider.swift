import Foundation
import UIKit

/// Independent song lookup for manually added radio streams. iHeart publishes
/// current tracks and history; ordinary HTTP audio streams may publish ICY titles. This
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
        // Some HLS stations put the actual on-air title, artist and cover URL
        // on each audio segment. That is closer to what VLC is playing than a
        // broadcaster API whose schedule can run ahead of the audio stream.
        var triedHLSURLs = Set<URL>()
        for candidate in station.streamCandidates.prefix(3)
        where candidate.pathExtension.lowercased() == "m3u8" {
            triedHLSURLs.insert(candidate)
            if let song = await hlsSong(from: candidate) { return song }
        }
        // The Beat's iHeart schedule is ahead of its HLS audio. If its
        // segment tags are briefly unavailable, keeping the last known song
        // is more accurate than displaying the scheduled next song early.
        if station.streamCandidates.contains(where: {
            $0.pathExtension.lowercased() == "m3u8" && KnownManualStation.iHeartID(for: $0) == 149
        }) {
            return .empty("The Beat HLS song tags temporarily unavailable")
        }
        // The listener's original URL can identify an iHeart station even
        // when its resolved CDN URL no longer contains the station ID. Ask
        // its published song feed directly instead of fetching a media
        // playlist on every metadata refresh.
        var triedIHeartIDs = Set<Int>()
        if let id = station.streamCandidates.compactMap(KnownManualStation.iHeartID(for:)).first {
            triedIHeartIDs.insert(id)
            let result = await iHeartSong(id: id)
            if result.hasTitle { return result }
        }

        // Check each candidate as soon as it resolves. Resolving every backup
        // playlist first can delay a working primary stream's song by tens of
        // seconds on cellular, even though VLC is already playing it.
        var streamsChecked = 0
        var programme: StreamMetadataUpdate?
        for candidate in station.streamCandidates.prefix(3) {
            guard let resolved = try? await ManualPlaylistResolver(httpClient: http).resolve(candidate) else {
                continue
            }
            for stream in resolved {
                guard streamsChecked < 3 else { break }
                streamsChecked += 1
                if let id = KnownManualStation.iHeartID(for: stream) {
                    guard triedIHeartIDs.insert(id).inserted else { continue }
                    let result = await iHeartSong(id: id)
                    if result.hasTitle { return result }
                    continue
                }
                // HLS and MPEG-TS carry timed metadata in their media. VLC
                // does not always surface it, so inspect the small HLS
                // playlist without opening another audio stream.
                if stream.pathExtension.lowercased() == "m3u8" {
                    if triedHLSURLs.insert(stream).inserted,
                       let song = await hlsSong(from: stream) { return song }
                    continue
                }
                if stream.pathExtension.lowercased() == "ts" { continue }
                if let title = await icyTitleReader(stream) {
                    let update = StreamMetadataParser.splittingCombinedTitle(
                        StreamMetadataUpdate(title: title, artist: nil, artworkData: nil)
                    )
                    if update.artist != nil { return .found(update) }
                    if programme == nil { programme = update }
                }
            }
            if streamsChecked >= 3 { break }
        }
        if let programme { return .found(programme) }
        return .empty("stream has no current song metadata")
    }

    private func hlsSong(from url: URL) async -> SongLookup? {
        guard let first = await playlist(at: url) else { return nil }
        let media: String
        if let variant = HLSPlaylistTrack.firstVariant(in: first.text, base: first.url),
           let resolved = await playlist(at: variant) {
            media = resolved.text
        } else {
            media = first.text
        }
        guard let track = HLSPlaylistTrack.firstOnAirTrack(in: media) else { return nil }
        return await songLookup(
            title: track.title,
            artist: track.artist,
            imagePath: track.artworkURL?.absoluteString,
            note: "HLS audio segment metadata"
        )
    }

    private func playlist(at url: URL) async -> (text: String, url: URL)? {
        var request = RequestBuilder.get(url, timeout: 6, userAgent: RequestBuilder.browserUserAgent)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL, */*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await http.data(for: request),
              (200..<300).contains(response.statusCode), data.count < 200_000,
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("#EXTM3U") else { return nil }
        return (text, response.url ?? url)
    }

    private func iHeartSong(id: Int) async -> SongLookup {
        // iHeart's current-track response can be ahead of trackHistory during
        // a song transition. The history response sometimes has only the song
        // that just ended, leaving a gap even while the new track is on air.
        let currentURL = URL(string: "https://us.api.iheart.com/api/v3/live-meta/stream/\(id)/currentTrackMeta?defaultMetadata=true")!
        if let (data, response) = try? await http.data(for: Self.iHeartRequest(currentURL)),
           (200..<300).contains(response.statusCode),
           let track = try? JSONDecoder().decode(Track.self, from: data),
           Self.currentTrack(in: [track], now: Date(), allowRecent: false) != nil {
            return await songLookup(for: track, note: "iHeart current track")
        }

        let url = URL(string: "https://us.api.iheart.com/api/v3/live-meta/stream/\(id)/trackHistory")!
        guard let (data, response) = try? await http.data(for: Self.iHeartRequest(url)),
              (200..<300).contains(response.statusCode),
              let history = try? JSONDecoder().decode(TrackHistory.self, from: data),
              let track = Self.currentTrack(in: history.data, now: Date()) else {
            return .empty("no current track in iHeart history")
        }

        return await songLookup(for: track, note: "iHeart track history")
    }

    private static func iHeartRequest(_ url: URL) -> URLRequest {
        var request = RequestBuilder.get(url, timeout: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func songLookup(for track: Track, note: String) async -> SongLookup {
        await songLookup(title: track.title, artist: track.artist, imagePath: track.imagePath, note: note)
    }

    private func songLookup(title: String, artist: String, imagePath: String?, note: String) async -> SongLookup {
        var artwork: Data?
        if let image = imagePath,
           var components = URLComponents(string: image) {
            components.scheme = "https"
            if let imageURL = components.url {
                artwork = await artworkCache.image(for: imageURL.absoluteString)
                if artwork == nil {
                    // Return the song immediately. The cover is fetched in the
                    // background and supplied on the next metadata check.
                    await artworkCache.prefetch(imageURL, using: http)
                }
            }
        }
        return .found(
            StreamMetadataUpdate(title: title, artist: artist, artworkData: artwork),
            note: note
        )
    }

    static func currentTrack(in tracks: [Track], now: Date, allowRecent: Bool = true) -> Track? {
        let timestamp = now.timeIntervalSince1970
        let valid = tracks.filter {
            !$0.title.isEmpty && !$0.artist.isEmpty &&
            $0.startTimestamp <= timestamp + 30
        }
        // The station history can lag the actual broadcast by a minute or
        // two. Prefer a current entry, then the newest recent entry so an
        // otherwise valid title and artwork do not disappear during that lag.
        let current = valid.filter { $0.endTimestamp >= timestamp - 15 }
            .max(by: { $0.startTimestamp < $1.startTimestamp })
        guard allowRecent, current == nil else { return current }
        return valid.filter { $0.endTimestamp >= timestamp - 180 }
            .max(by: { $0.startTimestamp < $1.startTimestamp })
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

        // currentTrackMeta uses milliseconds; trackHistory uses seconds.
        private static func seconds(_ value: Int) -> TimeInterval {
            let timestamp = TimeInterval(value)
            return timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        }

        var startTimestamp: TimeInterval { Self.seconds(startTime) }
        var endTimestamp: TimeInterval { Self.seconds(endTime) }
    }
}

/// Song tags attached to audio segments in a live HLS media playlist.
/// Only playlist text is read; media segments are left to VLC.
struct HLSPlaylistTrack: Equatable {
    let title: String
    let artist: String
    let artworkURL: URL?

    static func firstVariant(in text: String, base: URL) -> URL? {
        let lines = text.components(separatedBy: .newlines)
        for index in lines.indices where lines[index].hasPrefix("#EXT-X-STREAM-INF:") {
            guard index + 1 < lines.count else { continue }
            let raw = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.hasPrefix("#"),
                  let url = URL(string: raw, relativeTo: base)?.absoluteURL,
                  ManualPlaylistResolver.validHTTPURL(url.absoluteString) != nil else { continue }
            return url
        }
        return nil
    }

    static func firstOnAirTrack(in text: String) -> HLSPlaylistTrack? {
        // A live playlist lists the oldest segment first. VLC may start there
        // when tuning, so using the last segment's tag can show the next song
        // while the listener still hears the previous one.
        guard let segment = text.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("#EXTINF:") }),
              let title = quotedValue("title", in: segment),
              let artist = quotedValue("artist", in: segment) else { return nil }
        // Do not skip a promo at the playback end of the window to report
        // the song in a later segment before it is audible.
        if let spot = quotedValue("song_spot", in: segment), spot != "M" { return nil }
        let art = quotedValue("amgArtworkURL", in: segment)
            .flatMap(ManualPlaylistResolver.validHTTPURL)
        return HLSPlaylistTrack(title: title, artist: artist, artworkURL: art)
    }

    private static func quotedValue(_ name: String, in line: String) -> String? {
        guard let key = line.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        var remainder = line[key.upperBound...]
        let escapedDelimiter = remainder.hasPrefix("\\\"")
        if escapedDelimiter { remainder = remainder.dropFirst() }
        guard remainder.first == "\"" else { return nil }
        remainder = remainder.dropFirst()
        var value = ""
        var escaped = false
        for character in remainder {
            if escaped {
                if escapedDelimiter && character == "\"" { break }
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                value.append(character)
            }
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private actor ManualTrackArtworkCache {
    private var images: [String: Data] = [:]
    private var inFlight = Set<String>()

    func image(for key: String) -> Data? { images[key] }

    func prefetch(_ url: URL, using http: HTTPClient) {
        let key = url.absoluteString
        guard images[key] == nil, inFlight.insert(key).inserted else { return }
        Task {
            defer { self.inFlight.remove(key) }
            guard let (data, response) = try? await http.data(for: RequestBuilder.get(url, timeout: 8)),
                  (200..<300).contains(response.statusCode),
                  !data.isEmpty, data.count < 5_000_000,
                  UIImage(data: data) != nil else { return }
            if self.images.count >= 30 { self.images.removeAll() }
            self.images[key] = data
        }
    }
}

/// Reads a few ICY metadata blocks, then closes the connection. Some stations
/// send an empty first block during transitions; their next block has the song.
/// The actual audio continues through VLC independently.
struct ICYMetadataReader: Sendable {
    func currentTitle(from url: URL) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 16
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
            for _ in 0..<2 {
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
