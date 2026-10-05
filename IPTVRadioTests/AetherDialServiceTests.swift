import XCTest
@testable import IPTVRadio

final class AetherDialServiceTests: XCTestCase {
    func testSearchUsesHomeCountryAndExcludesBrokenOrUnsafeEntries() async throws {
        let http = MockHTTP.client { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            XCTAssertEqual(items.first(where: { $0.name == "countrycode" })?.value, "US")
            XCTAssertEqual(items.first(where: { $0.name == "hidebroken" })?.value, "true")
            XCTAssertEqual(items.first(where: { $0.name == "tag" })?.value, "jazz")
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("Aether/") == true)
            let json = """
            [
              {"stationuuid":"11111111-1111-1111-1111-111111111111","name":"Coast Jazz",
               "url":"https://radio.example/old.pls","url_resolved":"https://radio.example/live.mp3",
               "favicon":"https://radio.example/logo.png","state":"California","country":"United States",
               "tags":"jazz,soul","codec":"MP3","bitrate":128,"lastcheckok":1},
              {"stationuuid":"22222222-2222-2222-2222-222222222222","name":"Broken",
               "url":"https://radio.example/broken","lastcheckok":0},
              {"stationuuid":"33333333-3333-3333-3333-333333333333","name":"Unsafe",
               "url":"file:///private/audio.mp3","lastcheckok":1}
            ]
            """
            return (200, Data(json.utf8))
        }
        let results = try await AetherDialService(httpClient: http).search(DialQuery(
            place: "", genre: "jazz", name: "", worldwide: false, homeCountryCode: "US"
        ))
        XCTAssertEqual(results.map(\.name), ["Coast Jazz"])
        XCTAssertEqual(results[0].streamURL.absoluteString, "https://radio.example/old.pls")
        XCTAssertEqual(results[0].previewURL.absoluteString, "https://radio.example/live.mp3")
        XCTAssertEqual(results[0].location, "California · United States")
        XCTAssertEqual(results[0].logoURL?.absoluteString, "https://radio.example/logo.png")
        let preview = results[0].previewStation(playbackURLs: [results[0].previewURL])
        XCTAssertEqual(preview.source, .manual)
        XCTAssertEqual(preview.streamURL, results[0].previewURL)
        XCTAssertEqual(preview.alternativeStreamURLs, [results[0].streamURL])
    }

    func testPlaceSearchMergesStateAndCountryWithoutDuplicates() async throws {
        let http = MockHTTP.client { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let isState = items.contains { $0.name == "state" && $0.value == "California" }
            let first = """
            {"stationuuid":"11111111-1111-1111-1111-111111111111","name":"One",
             "url_resolved":"https://radio.example/one","lastcheckok":1}
            """
            let second = """
            {"stationuuid":"22222222-2222-2222-2222-222222222222","name":"Two",
             "url":"https://radio.example/two","lastcheckok":"1"}
            """
            return (200, Data((isState ? "[\(first)]" : "[\(first),\(second)]").utf8))
        }
        let results = try await AetherDialService(httpClient: http).search(DialQuery(
            place: "California", genre: nil, name: "", worldwide: false, homeCountryCode: "US"
        ))
        XCTAssertEqual(results.map(\.name), ["One", "Two"])
    }

    func testDirectoryUsesSecondMirrorWhenFirstIsUnavailable() async throws {
        let http = MockHTTP.client { request in
            if request.url?.host == "de1.api.radio-browser.info" {
                return (503, Data())
            }
            let json = """
            [{"stationuuid":"44444444-4444-4444-4444-444444444444","name":"Second Mirror",
              "url":"https://radio.example/live.mp3","lastcheckok":1}]
            """
            return (200, Data(json.utf8))
        }
        let results = try await AetherDialService(httpClient: http).search(DialQuery(
            place: "", genre: nil, name: "", worldwide: false, homeCountryCode: "US"
        ))
        XCTAssertEqual(results.first?.name, "Second Mirror")
    }
}
