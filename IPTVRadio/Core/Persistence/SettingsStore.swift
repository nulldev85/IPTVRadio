import Foundation

/// User-selectable playback engine. The VLC-based compatibility engine plays
/// the widest range of provider streams; AVPlayer is Apple's built-in engine.
enum PlaybackEngineKind: String, CaseIterable, Identifiable, Codable {
    case vlc
    case avplayer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vlc: return "Compatibility (VLC)"
        case .avplayer: return "Standard (AVPlayer)"
        }
    }

    var detail: String {
        switch self {
        case .vlc:
            return "Plays the widest range of provider streams, including raw MPEG-TS and audio-only endpoints."
        case .avplayer:
            return "Apple's built-in engine. Use it if the compatibility engine has trouble with your provider."
        }
    }
}

/// User-selectable stream format order. Lets users A/B test audio quality on
/// device, since providers differ in which format carries the original stream.
enum StreamFormatPreference: String, CaseIterable, Identifiable, Codable {
    /// Original MPEG-TS first (matches most IPTV players), HLS fallback.
    case automatic
    /// HLS manifest first, MPEG-TS fallback.
    case hlsFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic (recommended)"
        case .hlsFirst: return "HLS first"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Tries the provider's audio-only endpoints first (MP3/AAC), then the original MPEG-TS stream, then HLS."
        case .hlsFirst:
            return "Tries the audio-only endpoints first, then HLS before the MPEG-TS stream."
        }
    }
}

/// User preferences backed by UserDefaults, mirrored as @Published so SwiftUI
/// reacts immediately. Contains no secrets.
@MainActor
final class SettingsStore: ObservableObject {
    enum Keys {
        static let cellularAllowed = "settings.cellularAllowed"
        static let streamTimeout = "settings.streamTimeout"
        static let retryLimit = "settings.retryLimit"
        static let showAllStations = "settings.showAllStations"
        static let siriusOnly = "settings.siriusOnly"
        static let detectionRules = "settings.detectionRules"
        static let authMode = "settings.authMode"
        static let streamFormatPreference = "settings.streamFormatPreference"
        static let preferAudioOnlyRendition = "settings.preferAudioOnlyRendition"
        static let lookupSongArtwork = "settings.lookupSongArtwork"
        static let playbackEngine = "settings.playbackEngine"
    }

    enum AuthMode: String, CaseIterable, Identifiable {
        case xtream
        case m3u
        var id: String { rawValue }
    }

    private let defaults: UserDefaults

    @Published var cellularAllowed: Bool { didSet { defaults.set(cellularAllowed, forKey: Keys.cellularAllowed) } }
    /// Stream readiness timeout in seconds (5...60).
    @Published var streamTimeout: Double { didSet { defaults.set(streamTimeout, forKey: Keys.streamTimeout) } }
    /// Automatic retry attempts before surfacing failure (0...5).
    @Published var retryLimit: Int { didSet { defaults.set(retryLimit, forKey: Keys.retryLimit) } }
    /// Show the "All radio stations" browse option.
    @Published var showAllStations: Bool { didSet { defaults.set(showAllStations, forKey: Keys.showAllStations) } }
    /// Restrict the main tab to SiriusXM-labelled stations only.
    @Published var siriusOnly: Bool { didSet { defaults.set(siriusOnly, forKey: Keys.siriusOnly) } }
    /// Which sign-in mode was last used.
    @Published var authMode: AuthMode { didSet { defaults.set(authMode.rawValue, forKey: Keys.authMode) } }
    /// Configurable detection rules.
    @Published var detectionRules: RadioDetectionRules { didSet { persistRules() } }
    /// Stream format order used when building playback candidates.
    @Published var streamFormatPreference: StreamFormatPreference {
        didSet { defaults.set(streamFormatPreference.rawValue, forKey: Keys.streamFormatPreference) }
    }
    /// Prefer a stream's dedicated audio-only rendition over its video variant
    /// when the HLS manifest offers one (recommended for radio listening).
    @Published var preferAudioOnlyRendition: Bool {
        didSet { defaults.set(preferAudioOnlyRendition, forKey: Keys.preferAudioOnlyRendition) }
    }
    /// Look up song artwork online (Apple's public catalog) for streams that
    /// carry text metadata only.
    @Published var lookupSongArtwork: Bool {
        didSet { defaults.set(lookupSongArtwork, forKey: Keys.lookupSongArtwork) }
    }
    /// Playback engine used for streams (takes effect after an app restart).
    @Published var playbackEngine: PlaybackEngineKind {
        didSet { defaults.set(playbackEngine.rawValue, forKey: Keys.playbackEngine) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cellularAllowed = defaults.object(forKey: Keys.cellularAllowed) as? Bool ?? true
        streamTimeout = defaults.object(forKey: Keys.streamTimeout) as? Double ?? 15
        retryLimit = defaults.object(forKey: Keys.retryLimit) as? Int ?? 2
        showAllStations = defaults.object(forKey: Keys.showAllStations) as? Bool ?? true
        siriusOnly = defaults.object(forKey: Keys.siriusOnly) as? Bool ?? false
        authMode = AuthMode(rawValue: defaults.string(forKey: Keys.authMode) ?? "") ?? .xtream
        streamFormatPreference = StreamFormatPreference(
            rawValue: defaults.string(forKey: Keys.streamFormatPreference) ?? ""
        ) ?? .automatic
        preferAudioOnlyRendition = defaults.object(forKey: Keys.preferAudioOnlyRendition) as? Bool ?? true
        lookupSongArtwork = defaults.object(forKey: Keys.lookupSongArtwork) as? Bool ?? true
        playbackEngine = PlaybackEngineKind(rawValue: defaults.string(forKey: Keys.playbackEngine) ?? "")
            ?? .vlc

        if let data = defaults.data(forKey: Keys.detectionRules),
           let rules = try? JSONDecoder().decode(RadioDetectionRules.self, from: data) {
            detectionRules = rules
        } else {
            detectionRules = .default
        }
    }

    func resetDetectionRules() {
        detectionRules = .default
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(detectionRules) {
            defaults.set(data, forKey: Keys.detectionRules)
        }
    }
}
