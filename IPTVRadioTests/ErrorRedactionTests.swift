import XCTest
@testable import IPTVRadio

final class ErrorRedactionTests: XCTestCase {
    func testRedactorRemovesUsernameAndPassword() {
        let redactor = Redactor(secrets: ["secretuser", "secretpass123"])
        let input = "GET https://host/live/secretuser/secretpass123/1.m3u8 failed"
        let output = redactor.redact(input)
        XCTAssertFalse(output.contains("secretuser"))
        XCTAssertFalse(output.contains("secretpass123"))
        XCTAssertTrue(output.contains("***"))
    }

    func testRedactorScrubsQueryCredentials() {
        let redactor = Redactor(secrets: [])
        let output = redactor.redact("https://host/player_api.php?username=abc&password=xyz&token=tt")
        XCTAssertFalse(output.contains("abc"))
        XCTAssertFalse(output.contains("xyz"))
        XCTAssertFalse(output.contains("tt&") || output.hasSuffix("token=tt"))
        XCTAssertTrue(output.contains("username=***"))
    }

    func testRedactorIgnoresShortSecrets() {
        let redactor = Redactor(secrets: ["ab", "cd"])
        XCTAssertEqual(redactor.redact("abcd still fine"), "abcd still fine")
    }

    func testCredentialsRedactorCoversAllSecrets() {
        let credentials = ProviderCredentials.xtream(
            XtreamCredentials(serverInput: "http://host:8080", username: "myuser1234", password: "mypass5678")
        )
        let redactor = credentials.redactor
        let full = "user=myuser1234 pass=mypass5678"
        XCTAssertFalse(redactor.redact(full).contains("myuser1234"))
        XCTAssertFalse(redactor.redact(full).contains("mypass5678"))
        // Non-secret text is left intact.
        XCTAssertTrue(redactor.redact("user=nobody").contains("nobody"))
    }

    func testProviderErrorMessagesNeverContainCredentialPlaceholders() {
        let credentials = Fixtures.makeCredentials()
        let redactor = ProviderCredentials.xtream(credentials).redactor
        let errors: [ProviderError] = [
            .invalidServerURL, .notAuthenticated, .unauthorized, .sessionExpired,
            .networkUnreachable, .timedOut, .serverError(status: 500),
            .malformedResponse("bad"), .emptyPlaylist, .insecureEndpointWarning, .cancelled,
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.contains(credentials.username))
            XCTAssertFalse(message.contains(credentials.password))
            XCTAssertFalse(redactor.redact(message).hasPrefix("***"), "Message should not be entirely secrets")
            XCTAssertFalse(message.lowercased().contains("http://"), "No URLs in error messages")
        }
    }

    func testInsecureEndpointWarningIsUserFriendly() {
        let message = ProviderError.insecureEndpointWarning.errorDescription ?? ""
        XCTAssertTrue(message.contains("HTTP"))
        XCTAssertFalse(message.contains("http://"))
    }
}
