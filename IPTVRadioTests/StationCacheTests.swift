import XCTest
@testable import IPTVRadio

@MainActor
final class StationCacheTests: XCTestCase {
    private func makeCache(folder: String) -> StationCache {
        StationCache(fileStore: JSONFileStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("\(folder)-\(UUID().uuidString)")
        ))
    }

    private func makeSnapshot() -> LibrarySnapshot {
        RadioStationDetector(rules: .default).buildSnapshot(channels: [
            RawChannel(
                name: "Test Radio",
                url: URL(string: "https://host.example/live/u/p/1.ts")!,
                group: "Music Radio",
                source: .xtream
            )
        ])
    }

    func testCacheRoundTrip() {
        let cache = makeCache(folder: "roundtrip")
        cache.store(makeSnapshot())

        let loaded = cache.load()
        XCTAssertEqual(loaded?.schemaVersion, CachedLibrary.currentSchemaVersion)
        XCTAssertEqual(loaded?.snapshot.allRadioStations.count, 1)
    }

    func testLegacyCacheWithoutSchemaVersionIsRejected() {
        // Old app versions wrote a cache without a schema version; those
        // stations carry stale stream URLs and must not be played.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        let fileStore = JSONFileStore(directory: folder)
        let legacyJSON = """
        {
          "snapshot": {
            "siriusStations": [],
            "radioStations": [
              {
                "id": "abc",
                "name": "Stale Station",
                "streamURL": "https://host.example/live/u/p/1.m3u8",
                "groupTitle": "Music",
                "source": "xtream"
              }
            ],
            "categories": [],
            "totalChannelsScanned": 1,
            "generatedAt": "2026-01-01T00:00:00Z"
          },
          "fetchedAt": "2026-01-01T00:00:00Z"
        }
        """
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(legacyJSON.utf8).write(to: fileStore.url(for: "library-cache.json"))

        let cache = StationCache(fileStore: fileStore)
        XCTAssertNil(cache.load(), "Caches from older app versions must be discarded")
    }

    func testExpiredCacheIsRejected() {
        let cache = makeCache(folder: "expired")
        cache.store(makeSnapshot())
        XCTAssertNil(cache.load(maxAge: -1))
    }
}
