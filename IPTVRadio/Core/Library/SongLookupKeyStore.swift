import Foundation

/// Per-station channel keys for the song lookup, set by the listener.
///
/// This is the escape hatch for the whole feature. Broadcaster channel keys are
/// not published anywhere authoritative, the panel's label for a channel is not
/// the key, and neither a lookup table nor name mangling can be complete. So
/// rather than leaving a station permanently unable to show a song, the key is
/// made editable: the diagnostics screen reports what was tried and what came
/// back, and the listener can type the right one.
///
/// Deliberately not part of `SettingsStore`: that is `@MainActor`, and this is
/// read from the song-lookup task on every poll. `UserDefaults` is thread-safe,
/// so a small Sendable wrapper avoids hopping to the main actor to read a
/// string.
///
/// SECURITY: holds a channel name, keyed by station id. No credentials, and
/// nothing here is ever part of a stream URL.
final class SongLookupKeyStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "songLookup.channelKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The listener's key for this station, if they set one.
    func key(for stationID: String) -> String? {
        guard let map = defaults.dictionary(forKey: storageKey) as? [String: String],
              let value = map[stationID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// Sets or clears the key for a station. An empty string clears it, so the
    /// field in the UI does not need a separate delete control.
    func setKey(_ key: String?, for stationID: String) {
        var map = (defaults.dictionary(forKey: storageKey) as? [String: String]) ?? [:]
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            map.removeValue(forKey: stationID)
        } else {
            map[stationID] = trimmed
        }
        defaults.set(map, forKey: storageKey)
    }
}

/// Resolves the channel keys to try for a station, in order.
///
/// One place, shared by every broadcaster source, so a key the listener sets
/// applies to all of them and the order is consistent: what the listener said,
/// then what the table knows, then shapes derived from the name.
struct ChannelKeyResolver: Sendable {
    let overrides: SongLookupKeyStore?

    init(overrides: SongLookupKeyStore? = nil) {
        self.overrides = overrides
    }

    func keys(for station: RadioStation) -> [String] {
        var keys: [String] = []
        // The listener's own key wins outright: they can see what failed.
        if let override = overrides?.key(for: station.id) {
            keys.append(SiriusXMChannelKeys.normalise(override))
        }
        // Then the known-channel table, which is why this works at all.
        if let known = SiriusXMChannelKeys.key(forStationNamed: station.name) {
            keys.append(known)
        }
        // Then guesses from the label, for channels not in the table.
        keys.append(contentsOf: SiriusXMNowPlayingProvider.candidateSlugs(for: station.name))

        var unique: [String] = []
        for key in keys where !key.isEmpty {
            if !unique.contains(key) { unique.append(key) }
        }
        // Bounded: this runs every poll for every source.
        return Array(unique.prefix(5))
    }
}
