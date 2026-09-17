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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cellularAllowed = defaults.object(forKey: Keys.cellularAllowed) as? Bool ?? true
        streamTimeout = defaults.object(forKey: Keys.streamTimeout) as? Double ?? 15
        retryLimit = defaults.object(forKey: Keys.retryLimit) as? Int ?? 2
        showAllStations = defaults.object(forKey: Keys.showAllStations) as? Bool ?? true
        siriusOnly = defaults.object(forKey: Keys.siriusOnly) as? Bool ?? false
        authMode = AuthMode(rawValue: defaults.string(forKey: Keys.authMode) ?? "") ?? .xtream

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
