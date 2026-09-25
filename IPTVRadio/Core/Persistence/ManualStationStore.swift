import Foundation

struct ManualStationInput {
    var name: String
    var streamURL: String
    var logoURL: String
}

enum ManualStationError: LocalizedError {
    case missingName
    case invalidStreamURL
    case invalidLogoURL
    case duplicate
    case missingStation
    case playlistUnavailable
    case playlistTooLarge
    case playlistEmpty
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingName: return "Enter a station name."
        case .invalidStreamURL: return "Enter a valid HTTP or HTTPS stream URL."
        case .invalidLogoURL: return "Enter a valid HTTP or HTTPS artwork URL, or leave it blank."
        case .duplicate: return "This stream is already in your Radio stations."
        case .missingStation: return "This station is no longer in your Radio stations."
        case .playlistUnavailable: return "The playlist could not be loaded. Check the link and try again."
        case .playlistTooLarge: return "The playlist is too large for a single station."
        case .playlistEmpty: return "The playlist did not contain a playable HTTP or HTTPS stream."
        case .saveFailed: return "The station could not be saved on this device. Try again."
        }
    }
}

struct ManualStationEntry: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    /// The URL the listener entered, retained for editing and playlist refresh.
    var streamURL: URL
    var logoURL: URL?
    var playbackURLs: [URL]

    var station: RadioStation {
        let first = playbackURLs.first ?? streamURL
        let alternatives = Array(playbackURLs.dropFirst()) + (first == streamURL ? [] : [streamURL])
        return RadioStation(
            id: "manual-\(id)",
            name: name,
            streamURL: first,
            groupTitle: Self.formatDescription(for: streamURL),
            logoURL: logoURL ?? KnownManualStation.logo(for: streamURL),
            source: .manual,
            alternativeStreamURLs: alternatives.isEmpty ? nil : alternatives
        )
    }

    static func formatDescription(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "MP3 stream"
        case "aac", "aacp": return "AAC stream"
        case "m3u8": return "HLS stream"
        case "m3u", "pls": return "Radio playlist"
        case "ogg", "opus": return "Ogg/Opus stream"
        case "flac": return "FLAC stream"
        default: return "Live stream"
        }
    }
}

/// Listener-added stations live independently of the provider's refreshed cache.
@MainActor
final class ManualStationStore: ObservableObject {
    @Published private(set) var entries: [ManualStationEntry]

    private let fileStore: JSONFileStore
    private let filename = "manual-stations.json"

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        entries = fileStore.load([ManualStationEntry].self, filename: filename) ?? []
    }

    func station(id: String) -> RadioStation? {
        entries.first(where: { $0.station.id == id })?.station
    }

    func move(id: String, by offset: Int) {
        var updated = entries
        guard let index = updated.firstIndex(where: { $0.id == id }),
              updated.indices.contains(index + offset) else { return }
        updated.swapAt(index, index + offset)
        do {
            try fileStore.saveThrowing(updated, filename: filename)
            entries = updated
        } catch {
            // Keep the displayed order consistent with what was saved.
        }
    }

    @discardableResult
    func save(
        _ input: ManualStationInput,
        editing id: String? = nil,
        httpClient: HTTPClient
    ) async throws -> RadioStation {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ManualStationError.missingName }
        guard let streamURL = ManualPlaylistResolver.validHTTPURL(input.streamURL) else {
            throw ManualStationError.invalidStreamURL
        }
        let logoText = input.logoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let logoURL: URL?
        if logoText.isEmpty {
            logoURL = nil
        } else {
            guard let valid = ManualPlaylistResolver.validHTTPURL(logoText) else {
                throw ManualStationError.invalidLogoURL
            }
            logoURL = valid
        }
        guard !entries.contains(where: { $0.id != id && $0.streamURL == streamURL }) else {
            throw ManualStationError.duplicate
        }
        if let id, !entries.contains(where: { $0.id == id }) {
            throw ManualStationError.missingStation
        }

        let playbackURLs = try await ManualPlaylistResolver(httpClient: httpClient).resolve(streamURL)
        // Check again after the network request, in case another save completed.
        guard !entries.contains(where: { $0.id != id && $0.streamURL == streamURL }) else {
            throw ManualStationError.duplicate
        }
        let entry = ManualStationEntry(
            id: id ?? UUID().uuidString,
            name: name,
            streamURL: streamURL,
            logoURL: logoURL,
            playbackURLs: playbackURLs
        )
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == entry.id }) {
            updated[index] = entry
        } else {
            updated.insert(entry, at: 0)
        }
        do {
            try fileStore.saveThrowing(updated, filename: filename)
        } catch {
            throw ManualStationError.saveFailed
        }
        entries = updated
        return entry.station
    }

    func remove(id: String) throws {
        let updated = entries.filter { $0.id != id }
        guard updated.count != entries.count else { return }
        do {
            try fileStore.saveThrowing(updated, filename: filename)
        } catch {
            throw ManualStationError.saveFailed
        }
        entries = updated
    }
}

/// Logos for the local streams Aether can identify from their public URLs.
/// A listener-supplied artwork URL always takes priority.
enum KnownManualStation {
    static func hasICYMetadata(for url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return (value.contains("streamtheworld.com") && value.contains("kseqfm"))
            || (value.contains("securenetsystems.net") && value.contains("/kfrr"))
    }

    static func iHeartID(for url: URL) -> Int? {
        let value = url.absoluteString.lowercased()
        guard value.contains("ihrhls.com") || value.contains("iheart.com") else { return nil }
        if value.contains("/zc141/") || value.hasSuffix("/zc141") { return 141 }
        if value.contains("/zc149/") || value.hasSuffix("/zc149") { return 149 }
        return nil
    }

    static func logo(for url: URL) -> URL? {
        let value = url.absoluteString.lowercased()
        let image: String
        if iHeartID(for: url) == 141 {
            image = "https://i.iheart.com/v3/re/new_assets/5c5101e64d72695564fee9ef"
        } else if iHeartID(for: url) == 149 {
            image = "https://i.iheart.com/v3/re/new_assets/5f3b4852529439aac0159458"
        } else if value.contains("streamtheworld.com") && value.contains("kseqfm") {
            image = "https://dehayf5mhw1h7.cloudfront.net/wp-content/uploads/sites/2155/2023/08/03135133/rseq-logo.png"
        } else if value.contains("securenetsystems.net") && value.contains("/kfrr") {
            image = "https://dehayf5mhw1h7.cloudfront.net/wp-content/uploads/sites/2808/2026/06/03141205/kfrr-logo.webp"
        } else {
            return nil
        }
        return URL(string: image)
    }
}
