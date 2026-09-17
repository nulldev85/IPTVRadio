import XCTest
@testable import IPTVRadio

final class XtreamDecodingTests: XCTestCase {
    func testDecodeAuthResponseWithMixedTypes() throws {
        let response = try XtreamDecoder.decodeAuth(Data(Fixtures.authResponseJSON.utf8))
        let info = try XCTUnwrap(response.userInfo)
        XCTAssertEqual(info.auth, 1)
        XCTAssertEqual(info.status, "Active")
        XCTAssertEqual(info.maxConnections, "2")
        let server = try XCTUnwrap(response.serverInfo)
        XCTAssertEqual(server.httpsPort, "443")
    }

    func testDecodeAuthResponseMissingFieldsDoesNotThrow() throws {
        let json = #"{"user_info": null}"#
        let response = try XtreamDecoder.decodeAuth(Data(json.utf8))
        XCTAssertNil(response.userInfo)
        XCTAssertNil(response.serverInfo)
    }

    func testDecodeAuthMalformedThrowsProviderError() {
        XCTAssertThrowsError(try XtreamDecoder.decodeAuth(Data("not json".utf8))) { error in
            guard case ProviderError.malformedResponse = error else {
                return XCTFail("Expected malformedResponse, got \(error)")
            }
        }
    }

    func testDecodeCategories() throws {
        let categories = try XtreamDecoder.decodeCategories(Data(Fixtures.categoriesJSON.utf8))
        XCTAssertEqual(categories.count, 4)
        XCTAssertEqual(categories[0].categoryID, "1")
        XCTAssertEqual(categories[0].categoryName, "SiriusXM")
    }

    func testDecodeCategoriesWithNumericIDs() throws {
        let json = #"[{"category_id": 7, "category_name": "Radio"}]"#
        let categories = try XtreamDecoder.decodeCategories(Data(json.utf8))
        XCTAssertEqual(categories.first?.categoryID, "7")
    }

    func testDecodeLiveStreamsHandlesNulls() throws {
        let streams = try XtreamDecoder.decodeLiveStreams(Data(Fixtures.liveStreamsJSON.utf8))
        XCTAssertEqual(streams.count, 6)
        let octane = try XCTUnwrap(streams.first { $0.name == "SiriusXM Octane" })
        XCTAssertNil(octane.streamIcon)
        XCTAssertEqual(octane.streamID, "8021")
    }

    func testDecodeLiveStreamsNumericStreamID() throws {
        let json = #"[{"name": "FM Test", "stream_id": 12345, "stream_type": "live"}]"#
        let streams = try XtreamDecoder.decodeLiveStreams(Data(json.utf8))
        XCTAssertEqual(streams.first?.streamID, "12345")
    }

    func testDecodeLiveStreamsReadsContainerExtension() throws {
        let json = #"[{"name": "Radio Test", "stream_id": "1", "stream_type": "radio", "container_extension": "ts"}]"#
        let streams = try XtreamDecoder.decodeLiveStreams(Data(json.utf8))
        XCTAssertEqual(streams.first?.containerExtension, "ts")
    }

    func testDecodeLiveStreamsMissingContainerExtensionIsNil() throws {
        let streams = try XtreamDecoder.decodeLiveStreams(Data(Fixtures.liveStreamsJSON.utf8))
        XCTAssertNil(streams.first?.containerExtension)
    }

    // MARK: Session mapping

    func testSessionInfoPrefersHTTPS() throws {
        let response = try XtreamDecoder.decodeAuth(Data(Fixtures.authResponseJSON.utf8))
        let session = SessionInfo(authResponse: response, fallbackBase: nil)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.serverURL?.scheme, "https")
        XCTAssertTrue(session.serverURL?.absoluteString.contains("443") ?? false)
    }

    func testSessionInfoExpiryParsed() throws {
        let response = try XtreamDecoder.decodeAuth(Data(Fixtures.authResponseJSON.utf8))
        let session = SessionInfo(authResponse: response, fallbackBase: nil)
        let expiry = try XCTUnwrap(session.expiryDate)
        XCTAssertEqual(expiry.timeIntervalSince1970, 4_102_444_800, accuracy: 1)
        XCTAssertFalse(session.isExpired)
    }

    func testSessionInfoExpiredDetected() throws {
        let response = try XtreamDecoder.decodeAuth(Data(Fixtures.authExpiredJSON.utf8))
        let session = SessionInfo(authResponse: response, fallbackBase: nil)
        XCTAssertTrue(session.isExpired)
    }

    func testSessionInfoHTTPReportedAsInsecure() throws {
        let json = """
        { "user_info": {"auth": 1}, "server_info": {"url": "provider.example.net", "port": "80"} }
        """
        let response = try XtreamDecoder.decodeAuth(Data(json.utf8))
        let session = SessionInfo(authResponse: response, fallbackBase: nil)
        XCTAssertTrue(session.usesInsecureHTTP)
    }
}
