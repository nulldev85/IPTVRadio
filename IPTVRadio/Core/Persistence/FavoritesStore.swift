import Foundation

/// Favorites persisted as a JSON file keyed by station id.
@MainActor
final class FavoritesStore: ObservableObject {
    struct Entry: Codable, Hashable, Identifiable {
        var id: String { station.id }
        var station: RadioStation
        var addedAt: Date
    }

    private let fileStore: JSONFileStore
    private let filename = "favorites.json"
    private var entriesByID: [String: Entry] = [:]

    @Published private(set) var favorites: [Entry] = []

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        load()
    }

    var stationIDs: Set<String> { Set(entriesByID.keys) }

    func isFavorite(_ station: RadioStation) -> Bool {
        entriesByID[station.id] != nil
    }

    func toggle(_ station: RadioStation) {
        if isFavorite(station) {
            remove(station)
        } else {
            add(station)
        }
    }

    func add(_ station: RadioStation) {
        entriesByID[station.id] = Entry(station: station, addedAt: Date())
        persist()
    }

    func remove(_ station: RadioStation) {
        entriesByID.removeValue(forKey: station.id)
        persist()
    }

    func station(id: String) -> RadioStation? {
        entriesByID[id]?.station
    }

    /// Replaces entries saved by older app versions with the current library's
    /// station data (fresh stream URLs and format candidates), matching by
    /// name and source. Entries with no fresh match are kept as-is.
    func reconcile(with stations: [RadioStation]) {
        guard !entriesByID.isEmpty, !stations.isEmpty else { return }
        var index: [String: RadioStation] = [:]
        for station in stations {
            index[Self.matchKey(name: station.name, source: station.source)] = station
        }
        var changed = false
        var updated: [String: Entry] = [:]
        for (_, entry) in entriesByID {
            let key = Self.matchKey(name: entry.station.name, source: entry.station.source)
            if let fresh = index[key], fresh.id != entry.station.id {
                updated[fresh.id] = Entry(station: fresh, addedAt: entry.addedAt)
                changed = true
            } else {
                updated[entry.station.id] = entry
            }
        }
        if changed {
            entriesByID = updated
            persist()
        }
    }

    static func matchKey(name: String, source: RadioStation.Source) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "|" + source.rawValue
    }

    private func load() {
        let entries = fileStore.load([String: Entry].self, filename: filename) ?? [:]
        entriesByID = entries
        favorites = entries.values.sorted { $0.addedAt > $1.addedAt }
    }

    private func persist() {
        fileStore.save(entriesByID, filename: filename)
        favorites = entriesByID.values.sorted { $0.addedAt > $1.addedAt }
    }
}
