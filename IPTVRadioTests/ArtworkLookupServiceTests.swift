import XCTest
@testable import IPTVRadio

final class ArtworkLookupServiceTests: XCTestCase {
    func testReturnsArtworkDataAndUpscalesURL() async {
        let searchJSON = #"{"results":[{"artworkUrl100":"https://art.example/100x100bb.jpg"}]}"#
        let imageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
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

    func testTemporaryFailureCanRecoverOnNextLookup() async {
        let counter = RequestCounter()
        let imageData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let http = MockHTTP.client { request in
            if request.url?.host == "itunes.apple.com" {
                counter.increment()
                if counter.value == 1 { return (503, Data()) }
                return (200, Data(#"{"results":[{"artworkUrl100":"https://art.example/100x100bb.jpg"}]}"#.utf8))
            }
            return (200, imageData)
        }
        let service = ArtworkLookupService(http: http)
        let first = await service.artworkData(artist: "Artist", title: "Song")
        let second = await service.artworkData(artist: "Artist", title: "Song")
        XCTAssertNil(first)
        XCTAssertEqual(second, imageData)
        XCTAssertEqual(counter.value, 2)
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
