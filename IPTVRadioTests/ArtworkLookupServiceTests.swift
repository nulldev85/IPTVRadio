import XCTest
@testable import IPTVRadio

final class ArtworkLookupServiceTests: XCTestCase {
    func testReturnsArtworkDataAndUpscalesURL() async {
        let searchJSON = #"{"results":[{"artworkUrl100":"https://art.example/100x100bb.jpg"}]}"#
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let http = MockHTTP.client { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("itunes.apple.com/search") {
                return (200, Data(searchJSON.utf8))
            }
            if url.contains("art.example") {
                XCTAssertTrue(url.contains("600x600"), "Artwork URL should be requested at higher resolution")
                return (200, imageData)
            }
            return (404, Data())
        }
        let service = ArtworkLookupService(http: http)

        let data = await service.artworkData(artist: "Daft Punk", title: "Around the World")
        XCTAssertEqual(data, imageData)
    }

    func testReturnsNilWhenNoCatalogMatch() async {
        let http = MockHTTP.client { _ in (200, Data(#"{"results":[]}"#.utf8)) }
        let service = ArtworkLookupService(http: http)
        let data = await service.artworkData(artist: "Unknown Artist", title: "Unknown Song")
        XCTAssertNil(data)
    }

    func testBlankInputNeverRequests() async {
        let http = MockHTTP.client { request in
            XCTFail("Blank artist/title must not trigger a lookup: \(request.url?.absoluteString ?? "")")
            return (200, Data())
        }
        let service = ArtworkLookupService(http: http)
        let data = await service.artworkData(artist: "", title: " ")
        XCTAssertNil(data)
    }

    func testNegativeResultsAreCached() async {
        let counter = RequestCounter()
        let http = MockHTTP.client { _ in
            counter.increment()
            return (200, Data(#"{"results":[]}"#.utf8))
        }
        let service = ArtworkLookupService(http: http)

        _ = await service.artworkData(artist: "Nobody", title: "Nothing")
        _ = await service.artworkData(artist: "Nobody", title: "Nothing")
        XCTAssertEqual(counter.value, 1, "A song with no match must not be looked up repeatedly")
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
