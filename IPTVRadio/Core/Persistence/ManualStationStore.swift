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
            logoURL: logoURL,
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
