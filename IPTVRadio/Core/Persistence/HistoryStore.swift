import Foundation

/// Recently played stations, newest first, capped at 50 entries.
@MainActor
final class HistoryStore: ObservableObject {
    struct Entry: Codable, Hashable, Identifiable {
        var id: String { station.id }
        var station: RadioStation
        var playedAt: Date
    }

    static let maxEntries = 50

    private let fileStore: JSONFileStore
    private let filename = "history.json"

    @Published private(set) var entries: [Entry] = []

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        load()
    }

    func record(_ station: RadioStation) {
        var updated = entries.filter { $0.station.id != station.id }
        updated.insert(Entry(station: station, playedAt: Date()), at: 0)
        if updated.count > Self.maxEntries {
            updated.removeLast(updated.count - Self.maxEntries)
        }
        entries = updated
        fileStore.save(updated, filename: filename)
    }

    func clear() {
        entries = []
        fileStore.remove(filename: filename)
    }

    /// Replaces entries saved by older app versions with the current library's
    /// station data (fresh stream URLs and format candidates), matching by
    /// name and source. Entries with no fresh match are kept as-is.
    func reconcile(with stations: [RadioStation]) {
        guard !entries.isEmpty, !stations.isEmpty else { return }
        var index: [String: RadioStation] = [:]
        for station in stations {
            index[FavoritesStore.matchKey(name: station.name, source: station.source)] = station
        }
        var seen = Set<String>()
        var changed = false
        var updated: [Entry] = []
        for entry in entries {
            let key = FavoritesStore.matchKey(name: entry.station.name, source: entry.station.source)
            let resolved: RadioStation
            if let fresh = index[key], fresh.id != entry.station.id {
                resolved = fresh
                changed = true
            } else {
                resolved = entry.station
            }
            // De-duplicate if the migration produced two entries for one station.
            guard seen.insert(resolved.id).inserted else {
                changed = true
                continue
            }
            updated.append(Entry(station: resolved, playedAt: entry.playedAt))
        }
        if changed {
            entries = updated
            fileStore.save(updated, filename: filename)
        }
    }

    private func load() {
        entries = fileStore.load([Entry].self, filename: filename) ?? []
    }
}
