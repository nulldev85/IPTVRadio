import Foundation

/// Cached provider snapshot used for offline access and instant startup.
struct CachedLibrary: Codable {
    /// Bump when the cached shape changes (e.g. new stream format candidates,
    /// detection rules). Old caches are discarded instead of being shown and
    /// played, which would silently bypass app improvements.
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var snapshot: LibrarySnapshot
    var fetchedAt: Date
}

/// Persists the last successful library fetch.
@MainActor
final class StationCache: ObservableObject {
    private let fileStore: JSONFileStore
    private let filename = "library-cache.json"

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
    }

    func store(_ snapshot: LibrarySnapshot) {
        let cached = CachedLibrary(
            schemaVersion: CachedLibrary.currentSchemaVersion,
            snapshot: snapshot,
            fetchedAt: Date()
        )
        fileStore.save(cached, filename: filename)
    }

    func load(maxAge: TimeInterval = .days(7)) -> CachedLibrary? {
        guard let cached = fileStore.load(CachedLibrary.self, filename: filename) else { return nil }
        guard cached.schemaVersion == CachedLibrary.currentSchemaVersion else { return nil }
        guard Date().timeIntervalSince(cached.fetchedAt) <= maxAge else { return nil }
        return cached
    }

    func clear() {
        fileStore.remove(filename: filename)
    }
}

extension TimeInterval {
    static func days(_ days: Double) -> TimeInterval { days * 24 * 60 * 60 }
}
