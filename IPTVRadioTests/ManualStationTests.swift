import XCTest
@testable import IPTVRadio

@MainActor
final class ManualStationTests: XCTestCase {
    private func makeStore() -> (ManualStationStore, JSONFileStore) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-stations-\(UUID().uuidString)")
        let files = JSONFileStore(directory: folder)
        return (ManualStationStore(fileStore: files), files)
    }

    func testDirectStreamPersistsAndEditKeepsIdentity() async throws {
        let (store, files) = makeStore()
        let http = MockHTTP.client { _ in XCTFail("Direct streams must not be fetched when saved"); return (500, Data()) }

        let original = try await store.save(
            ManualStationInput(name: "  Jazz FM  ", streamURL: "https://radio.example.org/live.mp3", logoURL: ""),
            httpClient: http
        )
        XCTAssertEqual(original.name, "Jazz FM")
        XCTAssertEqual(original.groupTitle, "MP3 stream")
        XCTAssertEqual(original.source, .manual)

        let reloaded = ManualStationStore(fileStore: files)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries[0].station.id, original.id)

        let edited = try await reloaded.save(
            ManualStationInput(name: "Jazz Radio", streamURL: "https://radio.example.org/new.aac", logoURL: ""),
            editing: reloaded.entries[0].id,
            httpClient: http
        )
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.streamURL.absoluteString, "https://radio.example.org/new.aac")
        XCTAssertEqual(ManualStationStore(fileStore: files).entries[0].station.name, "Jazz Radio")

        try reloaded.remove(id: reloaded.entries[0].id)
        XCTAssertTrue(ManualStationStore(fileStore: files).entries.isEmpty)
    }

    func testValidationAndDuplicatePrevention() async throws {
        let (store, _) = makeStore()
        let http = MockHTTP.client { _ in (500, Data()) }
        do {
            _ = try await store.save(
                ManualStationInput(name: "Bad", streamURL: "file:///private/stream.mp3", logoURL: ""),
                httpClient: http
            )
            XCTFail("A local file URL should be rejected")
        } catch ManualStationError.invalidStreamURL {}

        let input = ManualStationInput(name: "One", streamURL: "https://radio.example.org/live", logoURL: "")
        _ = try await store.save(input, httpClient: http)
        do {
            _ = try await store.save(input, httpClient: http)
            XCTFail("The same stream should not be added twice")
        } catch ManualStationError.duplicate {}
    }

    func testM3UAndPLSResolveToDirectStreams() async throws {
        let m3u = MockHTTP.client { _ in
            (200, Data("#EXTM3U\n#EXTINF:-1,Radio\n/live.mp3\nhttps://edge.example.org/backup.aac\n".utf8))
        }
        let m3uURLs = try await ManualPlaylistResolver(httpClient: m3u)
            .resolve(URL(string: "https://radio.example.org/station.m3u")!)
        XCTAssertEqual(m3uURLs.map(\.absoluteString), [
            "https://radio.example.org/live.mp3",
            "https://edge.example.org/backup.aac"
        ])

        let pls = MockHTTP.client { _ in
            (200, Data("[playlist]\nFile2=https://radio.example.org/backup.aac\nFile1=https://radio.example.org/live.mp3\n".utf8))
        }
        let plsURLs = try await ManualPlaylistResolver(httpClient: pls)
            .resolve(URL(string: "https://radio.example.org/station.pls")!)
        XCTAssertEqual(plsURLs.map(\.lastPathComponent), ["live.mp3", "backup.aac"])
    }
}
