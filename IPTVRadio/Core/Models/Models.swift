import Foundation

/// A radio station normalized from any provider source (Xtream or M3U).
struct RadioStation: Identifiable, Hashable, Codable, Sendable {
    enum Source: String, Codable, Hashable, Sendable {
        case xtream
        case m3u
    }

    /// Stable identifier derived from the source and stream URL.
    let id: String
    var name: String
    var streamURL: URL
    var groupTitle: String
    var logoURL: URL?
    var tvgID: String?
    var source: Source
    /// Extra stream formats for the same station, tried in order if the
    /// primary URL fails (e.g. original MPEG-TS vs transcoded HLS).
    var alternativeStreamURLs: [URL]?
    /// Xtream stream id, used to fetch song info from the provider's EPG API.
    var xtreamStreamID: String?

    /// All candidate URLs, primary first, de-duplicated.
    var streamCandidates: [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for url in [streamURL] + (alternativeStreamURLs ?? []) where seen.insert(url.absoluteString).inserted {
            urls.append(url)
        }
        return urls
    }

    init(
        name: String,
        streamURL: URL,
        groupTitle: String = "",
        logoURL: URL? = nil,
        tvgID: String? = nil,
        source: Source,
        alternativeStreamURLs: [URL]? = nil,
        xtreamStreamID: String? = nil
    ) {
        self.id = StationIdentifier.make(source: source, url: streamURL, name: name)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.streamURL = streamURL
        self.groupTitle = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.logoURL = logoURL
        self.tvgID = tvgID
        self.source = source
        self.alternativeStreamURLs = alternativeStreamURLs
        self.xtreamStreamID = xtreamStreamID
    }
}

/// Builds stable, non-reversible station identifiers.
enum StationIdentifier {
    static func make(source: RadioStation.Source, url: URL, name: String) -> String {
        let key = "\(source.rawValue)|\(url.absoluteString.lowercased())|\(name.lowercased())"
        return stableHash(key)
    }

    /// FNV-1a style digest rendered as hex. Not cryptographic; used only for
    /// stable identity and deduplication, never for secrets.
    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

/// A provider category/group (e.g. "SiriusXM", "Music Radio").
struct ChannelCategory: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Neutral representation of a channel before radio detection runs.
/// Both Xtream and M3U sources normalize into this type.
struct RawChannel: Hashable, Sendable {
    var name: String
    var url: URL
    var group: String
    var logoURL: URL?
    var tvgID: String?
    var source: RadioStation.Source
    var categoryID: String?
    /// Additional stream formats to try if `url` fails (primary first).
    var alternativeURLs: [URL]
    /// URL used for radio classification. Detection must not depend on format
    /// reordering (e.g. a `.ts` sibling would otherwise look like video);
    /// this is normally the URL exactly as the provider/playlist declared it.
    var analysisURL: URL?
    /// Xtream stream id, for EPG-based song info.
    var xtreamStreamID: String?

    init(
        name: String,
        url: URL,
        group: String = "",
        logoURL: URL? = nil,
        tvgID: String? = nil,
        source: RadioStation.Source,
        categoryID: String? = nil,
        alternativeURLs: [URL] = [],
        analysisURL: URL? = nil,
        xtreamStreamID: String? = nil
    ) {
        self.name = name
        self.url = url
        self.group = group
        self.logoURL = logoURL
        self.tvgID = tvgID
        self.source = source
        self.categoryID = categoryID
        self.alternativeURLs = alternativeURLs
        self.analysisURL = analysisURL
        self.xtreamStreamID = xtreamStreamID
    }
}

/// The result of running radio detection over raw channels.
struct LibrarySnapshot: Codable, Hashable, Sendable {
    var siriusStations: [RadioStation]
    var radioStations: [RadioStation]
    var categories: [ChannelCategory]
    var totalChannelsScanned: Int
    var generatedAt: Date

    var allRadioStations: [RadioStation] {
        // Sirius first, then the remaining radio stations, deduplicated.
        var seen = Set<String>()
        var out: [RadioStation] = []
        for station in siriusStations + radioStations where seen.insert(station.id).inserted {
            out.append(station)
        }
        return out
    }

    func stations(in category: ChannelCategory) -> [RadioStation] {
        allRadioStations.filter { station in
            CategoryNormalizer.matches(station.groupTitle, category: category)
        }
    }
}

/// Case/format tolerant matching of a station group title to a category.
enum CategoryNormalizer {
    static func normalized(_ value: String) -> String {
        value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ groupTitle: String, category: ChannelCategory) -> Bool {
        let a = normalized(groupTitle)
        let b = normalized(category.name)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b
    }
}
