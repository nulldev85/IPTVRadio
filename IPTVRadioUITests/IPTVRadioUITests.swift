import XCTest

/// UI tests run against the app in mock mode via launch arguments. No network
/// access and no real credentials are used.
final class IPTVRadioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMock", "-UITestScenario=\(scenario)"] + extraArguments
        app.launch()
        return app
    }

    func testLoginFlowShowsFormAndAuthorizesMockCredentials() throws {
        let app = launch(scenario: "UITestLogin")

        let serverField = app.textFields["login.server"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 10))

        serverField.tap()
        serverField.typeText("https://demo.example.net:8080")
        app.textFields["login.username"].tap()
        app.textFields["login.username"].typeText("uitest-user")
        app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText("uitest-pass")
        app.buttons["login.submit"].tap()

        // Mock mode: entering any Xtream credentials is accepted instantly and
        // shows the main interface.
        XCTAssertTrue(app.buttons["Radio"].waitForExistence(timeout: 8))
    }

    func testBrowseShowsStationsAndCategories() throws {
        let app = launch(scenario: "UITestBrowse")

        // SiriusXM stations are prioritized on the Radio tab.
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["SiriusXM Octane"].exists)

        app.buttons["Browse"].tap()
        let category = app.buttons["browse.category.SiriusXM"]
        XCTAssertTrue(category.waitForExistence(timeout: 8))
        category.tap()
        XCTAssertTrue(app.buttons["station.row.SiriusXM Hits 1"].waitForExistence(timeout: 8))
    }

    func testSearchFindsStationsByGenreAndName() throws {
        let app = launch(scenario: "UITestSearch")

        app.buttons["Search"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("Jazz")

        XCTAssertTrue(app.staticTexts["Jazz Cafe Radio"].waitForExistence(timeout: 8))
    }

    func testFavoritesToggleAndLibraryListing() throws {
        let app = launch(scenario: "UITestFavorites")

        // Two stations were favorited by the mock scenario.
        app.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Favorites"].exists)
    }

    func testNowPlayingScreenShowsStateAndControls() throws {
        let app = launch(scenario: "UITestNowPlaying")

        // Mini player visible with the playing station.
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["miniplayer.toggle"].exists)

        let miniPlayer = app.otherElements["miniplayer.open"].firstMatch
        if miniPlayer.exists {
            miniPlayer.tap()
        } else {
            app.staticTexts["SiriusXM Hits 1"].tap()
        }
        let done = app.buttons["nowplaying.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "Now playing screen should open")
        XCTAssertTrue(app.buttons["nowplaying.toggle"].exists)
        XCTAssertTrue(app.buttons["nowplaying.stop"].exists)
        XCTAssertTrue(app.buttons["nowplaying.sleepTimer"].exists)

        // Stop playback and dismiss.
        app.buttons["nowplaying.stop"].tap()
        done.tap()
    }
}
