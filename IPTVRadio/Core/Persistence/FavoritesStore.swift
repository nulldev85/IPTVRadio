import Foundation

/// Favorites persisted as a JSON file keyed by station id.
@MainActor
final class FavoritesStore: ObservableObject {
    struct Entry: Codable, Hashable, Identifiable {
        var id: String { station.id }
        var station: RadioStation
        var addedAt: Date
        var order: Int?
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
        let next = (entriesByID.values.compactMap(\.order).min() ?? 0) - 1
        entriesByID[station.id] = Entry(station: station, addedAt: Date(), order: next)
        persist()
    }

    func move(id: String, by offset: Int) {
        var ordered = favorites
        guard let index = ordered.firstIndex(where: { $0.id == id }),
              ordered.indices.contains(index + offset) else { return }
        ordered.swapAt(index, index + offset)
        for (index, var entry) in ordered.enumerated() {
            entry.order = index
            entriesByID[entry.id] = entry
        }
        persist()
    }

    func remove(_ station: RadioStation) {
        entriesByID.removeValue(forKey: station.id)
        persist()
    }

    /// Keeps a favorite's display and playback URL current after a manual edit.
    func replace(_ station: RadioStation) {
        guard var entry = entriesByID[station.id] else { return }
        entry.station = station
        entriesByID[station.id] = entry
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
                updated[fresh.id] = Entry(station: fresh, addedAt: entry.addedAt, order: entry.order)
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
        // Existing installations had no order field. Preserve the old
        // newest-first display before assigning stable positions.
        let ordered = entries.values.sorted {
            if let left = $0.order, let right = $1.order { return left < right }
            return $0.addedAt > $1.addedAt
        }
        for (index, var entry) in ordered.enumerated() {
            entry.order = index
            entriesByID[entry.id] = entry
        }
        favorites = ordered.enumerated().map { index, entry in
            var entry = entry
            entry.order = index
            return entry
        }
        if !entries.isEmpty && entries.values.contains(where: { $0.order == nil }) {
            fileStore.save(entriesByID, filename: filename)
        }
    }

    private func persist() {
        fileStore.save(entriesByID, filename: filename)
        favorites = entriesByID.values.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }
}
