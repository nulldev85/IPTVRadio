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
