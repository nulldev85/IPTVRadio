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

    private func load() {
        entries = fileStore.load([Entry].self, filename: filename) ?? []
    }
}
