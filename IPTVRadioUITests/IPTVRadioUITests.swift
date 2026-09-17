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
        let toggle = app.buttons["miniplayer.toggle"]
        if !toggle.waitForExistence(timeout: 8) {
            XCTFail("Mini player not visible. Hierarchy:\n\(app.debugDescription)")
        }

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
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

        // Stop playback, then dismiss with the always-visible control.
        app.buttons["nowplaying.stop"].tap()
        close.tap()

        // The user is returned to the station list with a persistent mini player.
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8))
    }

    /// The Close control must be a real, hittable, on-screen element while
    /// actively playing — not merely present in the accessibility tree. This
    /// inspects the actual laid-out frame, not just element existence.
    func testCloseControlIsOnScreenAndHittableWhilePlaying() throws {
        let app = launch(scenario: "UITestNowPlaying")

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        miniPlayer.tap()

        let close = app.buttons["nowplaying.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(close.isHittable, "Close control exists but is not hittable. Hierarchy:\n\(app.debugDescription)")

        let windowFrame = app.windows.firstMatch.frame
        let closeFrame = close.frame
        XCTAssertFalse(closeFrame.isEmpty, "Close control has a zero-size frame")
        XCTAssertTrue(windowFrame.contains(closeFrame), "Close control frame \(closeFrame) is outside the visible window \(windowFrame)")
        // It must sit near the top of the screen (the safe-area bar), not be
        // pushed off-screen or buried below other content.
        XCTAssertLessThan(closeFrame.minY, windowFrame.height * 0.25, "Close control is not positioned near the top of the screen")

        close.tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8), "Dismissing must return to the mini player, not trap the user")
    }

    /// The player can open directly into a failed/reconnecting state (e.g.
    /// cellular blocked). The Close control must still be present, on-screen
    /// and hittable — a real device shows this exact case when a stream
    /// drops and every automatic retry has failed.
    func testCloseControlIsOnScreenAndHittableWhileFailed() throws {
        let app = launch(scenario: "UITestNowPlayingError")

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        miniPlayer.tap()

        let close = app.buttons["nowplaying.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Close control missing while player is in a failed state. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(close.isHittable)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertTrue(windowFrame.contains(close.frame), "Close control is outside the visible window while failed")

        // The failed state itself must be visible alongside the Close control.
        XCTAssertTrue(app.staticTexts["nowplaying.state"].waitForExistence(timeout: 4))

        close.tap()
        XCTAssertTrue(app.buttons["miniplayer.open"].waitForExistence(timeout: 8))
    }

    /// Selecting a station must never force the full player open: only the
    /// persistent mini player should appear. The full player opens only when
    /// the user explicitly taps it, and dismissing it must let the user pick
    /// a different station afterward.
    func testSelectingStationShowsMiniPlayerOnlyAndAllowsSwitchingStations() throws {
        let app = launch(scenario: "UITestBrowse")

        let firstRow = app.buttons["station.row.SiriusXM Hits 1"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        firstRow.tap()

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8), "Mini player did not appear after selecting a station")
        XCTAssertFalse(app.buttons["nowplaying.close"].exists, "Full player must not open automatically when playback starts")

        miniPlayer.tap()
        let close = app.buttons["nowplaying.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()

        // Back at the station list: select a different station entirely.
        let secondRow = app.buttons["station.row.SiriusXM Octane"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 8))
        secondRow.tap()

        // StationRow only shows a "Live" badge for the currently-playing
        // station, so this proves playback actually switched, not merely
        // that the row's static label is still on screen.
        let deadline = Date().addingTimeInterval(8)
        var switchedToOctane = false
        while Date() < deadline {
            if secondRow.label.contains("Live") {
                switchedToOctane = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(switchedToOctane, "Selecting a second station did not switch playback. Row label: \(secondRow.label)")
    }

    /// The temporary diagnostics panel must be reachable from the player and
    /// show non-secret playback details (codec, sample rate, channels,
    /// bitrate, route, direct-source usage) without ever showing a URL,
    /// username, password or token.
    func testDiagnosticsPanelShowsNonSecretPlaybackDetails() throws {
        let app = launch(scenario: "UITestNowPlaying")

        let miniPlayer = app.buttons["miniplayer.open"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        miniPlayer.tap()

        let diagnosticsButton = app.buttons["nowplaying.diagnostics"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 8))
        diagnosticsButton.tap()

        XCTAssertTrue(app.staticTexts["diagnostics.value.codec"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["diagnostics.value.codec"].label, "AAC")
        XCTAssertEqual(app.staticTexts["diagnostics.value.channels"].label, "2 (stereo)")
        XCTAssertEqual(app.staticTexts["diagnostics.value.sampleRate"].label, "44.1 kHz")

        // SECURITY: never a URL, username or password anywhere on the panel.
        let fullDescription = app.debugDescription
        XCTAssertFalse(fullDescription.contains("testuser"))
        XCTAssertFalse(fullDescription.contains("testpass"))
        XCTAssertFalse(fullDescription.lowercased().contains("http://"))
        XCTAssertFalse(fullDescription.lowercased().contains("https://"))

        app.buttons["diagnostics.done"].tap()
        XCTAssertTrue(app.buttons["nowplaying.close"].waitForExistence(timeout: 8), "Closing diagnostics must return to the player, not lose the Close control")
    }
}
