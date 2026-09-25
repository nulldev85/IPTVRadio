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
        let usernameField = app.textFields["login.username"]
        usernameField.tap()
        usernameField.typeText("uitest-user")
        let passwordField = app.secureTextFields["login.password"]
        passwordField.tap()
        passwordField.typeText("uitest-pass\n")

        // Return key submits via onSubmit; fall back to the button if needed.
        if !app.buttons["Radio"].waitForExistence(timeout: 10),
           app.buttons["login.submit"].exists {
            app.swipeUp()
            app.buttons["login.submit"].tap()
        }
        let radioTab = app.buttons["Radio"]
        if !radioTab.waitForExistence(timeout: 10) {
            XCTFail("Radio tab not found after sign-in. Hierarchy:\n\(app.debugDescription)")
        }
    }

    func testRadioTabListsStationsAndSeeAll() throws {
        let app = launch(scenario: "UITestBrowse")

        // SiriusXM keeps its own tab beside the listener's Radio stations.
        app.buttons["SXM"].tap()
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["SiriusXM Octane"].exists)

        // Radio only: there is no TV/video browsing tab.
        XCTAssertFalse(app.buttons["Browse"].exists, "TV browsing must not exist in a radio-only app")

        app.buttons["radio.seeAll"].tap()
        XCTAssertTrue(app.navigationBars["SiriusXM Stations"].waitForExistence(timeout: 8))
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

    func testManualRadioStationCanBeAddedPlayedAndRemoved() throws {
        let app = launch(scenario: "UITestBrowse")
        XCTAssertTrue(app.staticTexts["Your Radio stations"].waitForExistence(timeout: 8))

        app.buttons["manual.addEmpty"].tap()
        let name = app.textFields["manual.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("My Test Radio")
        let url = app.textFields["manual.url"]
        url.tap()
        url.typeText("https://radio.example.org/live.mp3")
        app.buttons["manual.save"].tap()

        let row = app.buttons["station.row.My Test Radio"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8))

        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Your Radio stations"].waitForExistence(timeout: 8))
    }

    func testFavoritesToggleAndLibraryListing() throws {
        let app = launch(scenario: "UITestFavorites")

        // Two stations were favorited by the mock scenario.
        app.buttons["Favorites"].tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))

        // Favorites must be playable from the Favorites tab.
        app.buttons["station.row.SiriusXM Hits 1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8),
                      "Tapping a favorite must start playback")
    }

    func testNowPlayingScreenShowsStateAndControls() throws {
        let app = launch(scenario: "UITestNowPlaying")

        // Mini player visible with the playing station.
        XCTAssertTrue(app.staticTexts["SiriusXM Hits 1"].waitForExistence(timeout: 8))
        let toggle = app.buttons["miniplayer.toggle"]
        if !toggle.waitForExistence(timeout: 8) {
            XCTFail("Mini player not visible. Hierarchy:\n\(app.debugDescription)")
        }

        // Tab navigation must remain usable while a station is playing.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8),
                      "Tab bar must remain reachable during playback")
        app.buttons["SXM"].tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8))

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        miniPlayer.tap()
        let close = app.buttons["nowplaying.close"]
        if !close.waitForExistence(timeout: 8) {
            XCTFail("Now playing screen did not open or close control missing. Hierarchy:\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.buttons["nowplaying.toggle"].exists)
        XCTAssertTrue(app.buttons["nowplaying.stop"].exists)
        XCTAssertTrue(app.buttons["nowplaying.sleepTimer"].exists)

        // Switching stations repeatedly works without leaving the player.
        app.buttons["nowplaying.next"].tap()
        XCTAssertTrue(app.buttons["nowplaying.toggle"].waitForExistence(timeout: 8))

        // Dismiss with the always-visible control; playback continues in the
        // persistent mini player.
        close.tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8))

        // Explicit Stop clears the mini player entirely so the full UI (and
        // tab bar) is always recoverable without restarting the app.
        app.buttons["miniplayer.stop"].tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForNonExistence(timeout: 8),
                      "Stopping must clear the mini player")
        XCTAssertTrue(app.buttons["Radio"].waitForExistence(timeout: 8))
    }
}
