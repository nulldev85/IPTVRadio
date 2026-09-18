import Foundation

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
        case .automatic: return "Automatic (MPEG-TS first)"
        case .hlsFirst: return "HLS first"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Plays the provider's original MPEG-TS stream when available, with HLS as a fallback."
        case .hlsFirst:
            return "Plays the HLS (.m3u8) manifest first, falling back to MPEG-TS."
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
