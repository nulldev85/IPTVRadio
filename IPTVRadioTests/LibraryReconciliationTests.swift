import XCTest
@testable import IPTVRadio

/// Favorites/history entries saved by older app versions must be migrated to
/// the current library's station data so they play fresh streams.
@MainActor
final class LibraryReconciliationTests: XCTestCase {
    private func makeDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    private func freshStation() -> RadioStation {
        let snapshot = RadioStationDetector(rules: .default).buildSnapshot(channels: [
            RawChannel(
                name: "Rock Radio",
                url: URL(string: "https://host.example/live/u/p/1.m3u8")!,
                group: "Music Radio",
                source: .xtream
            )
        ])
        guard let station = snapshot.allRadioStations.first else {
            fatalError("Fixture must produce a radio station")
        }
        return station
    }

    private func staleStation(name: String = "Rock Radio", path: String = "old/legacy-path.m3u8") -> RadioStation {
        RadioStation(
            name: name,
            streamURL: URL(string: "https://old.example/\(path)")!,
            groupTitle: "Music Radio",
            source: .xtream
        )
    }

    func testFavoritesMigrateToFreshStations() {
        let store = FavoritesStore(fileStore: JSONFileStore(directory: makeDirectory("fav")))
        let stale = staleStation()
        store.add(stale)
        let fresh = freshStation()
        XCTAssertNotEqual(stale.id, fresh.id)

        store.reconcile(with: [fresh])

        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(store.favorites.first?.station.id, fresh.id)
        XCTAssertTrue(store.isFavorite(fresh), "Fresh station must be recognized as favorited")
    }

    func testHistoryMigratesAndDeduplicates() {
        let store = HistoryStore(fileStore: JSONFileStore(directory: makeDirectory("hist")))
        store.record(staleStation(path: "old/one.m3u8"))
        store.record(staleStation(path: "old/two.m3u8"))
        XCTAssertEqual(store.entries.count, 2)

        store.reconcile(with: [freshStation()])

        XCTAssertEqual(store.entries.count, 1, "Both old entries map to the same fresh station")
        XCTAssertEqual(store.entries.first?.station.streamCandidates.count, 2)
    }

    func testUnknownStationsAreKeptUnchanged() {
        let store = FavoritesStore(fileStore: JSONFileStore(directory: makeDirectory("keep")))
        let unknown = staleStation(name: "Not In Library")
        store.add(unknown)

        store.reconcile(with: [freshStation()])

        XCTAssertEqual(store.favorites.first?.station.id, unknown.id,
                       "Stations without a fresh match must be preserved as-is")
    }
}
