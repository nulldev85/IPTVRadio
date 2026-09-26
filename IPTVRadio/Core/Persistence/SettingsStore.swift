import Foundation

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
        static let preferAudioOnlyRendition = "settings.preferAudioOnlyRendition"
        static let lookupSongArtwork = "settings.lookupSongArtwork"
        static let liquidGlassEnabled = "settings.liquidGlassEnabled"
        static let sonosOutputControl = "settings.sonosOutputControl"
        static let bluetoothOutputControl = "settings.bluetoothOutputControl"
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
    /// Use the system tab bar, including Liquid Glass on supported iOS versions.
    @Published var liquidGlassEnabled: Bool {
        didSet { defaults.set(liquidGlassEnabled, forKey: Keys.liquidGlassEnabled) }
    }
    /// Whether the Now Playing wireless output shortcut is shown for AirPlay speakers.
    @Published var sonosOutputControl: Bool {
        didSet { defaults.set(sonosOutputControl, forKey: Keys.sonosOutputControl) }
    }
    /// Whether the same system output shortcut is shown for Bluetooth audio devices.
    @Published var bluetoothOutputControl: Bool {
        didSet { defaults.set(bluetoothOutputControl, forKey: Keys.bluetoothOutputControl) }
    }
    /// Playback engine used for streams (takes effect after an app restart).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cellularAllowed = defaults.object(forKey: Keys.cellularAllowed) as? Bool ?? true
        streamTimeout = defaults.object(forKey: Keys.streamTimeout) as? Double ?? 15
        retryLimit = defaults.object(forKey: Keys.retryLimit) as? Int ?? 2
        showAllStations = defaults.object(forKey: Keys.showAllStations) as? Bool ?? true
        siriusOnly = defaults.object(forKey: Keys.siriusOnly) as? Bool ?? false
        authMode = AuthMode(rawValue: defaults.string(forKey: Keys.authMode) ?? "") ?? .xtream
        preferAudioOnlyRendition = defaults.object(forKey: Keys.preferAudioOnlyRendition) as? Bool ?? true
        lookupSongArtwork = defaults.object(forKey: Keys.lookupSongArtwork) as? Bool ?? true
        liquidGlassEnabled = defaults.object(forKey: Keys.liquidGlassEnabled) as? Bool ?? true
        sonosOutputControl = defaults.object(forKey: Keys.sonosOutputControl) as? Bool ?? true
        bluetoothOutputControl = defaults.object(forKey: Keys.bluetoothOutputControl) as? Bool ?? true

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
