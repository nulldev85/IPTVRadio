import XCTest
@testable import IPTVRadio

final class RetryPolicyTests: XCTestCase {
    func testRetryWhileAttemptsRemain() {
        let policy = RetryPolicy(maxAttempts: 3)
        XCTAssertEqual(policy.nextAction(afterAttempts: 0), .retryAfterDelay(1))
        XCTAssertEqual(policy.nextAction(afterAttempts: 1), .retryAfterDelay(2))
        XCTAssertEqual(policy.nextAction(afterAttempts: 2), .retryAfterDelay(4))
    }

    func testGiveUpAfterMaxAttempts() {
        let policy = RetryPolicy(maxAttempts: 3)
        XCTAssertEqual(policy.nextAction(afterAttempts: 3), .giveUp)
        XCTAssertEqual(policy.nextAction(afterAttempts: 10), .giveUp)
    }

    func testZeroMaxAttemptsGivesUpImmediately() {
        let policy = RetryPolicy(maxAttempts: 0)
        XCTAssertEqual(policy.nextAction(afterAttempts: 0), .giveUp)
    }

    func testBackoffIsExponential() {
        XCTAssertEqual(RetryPolicy.backoff(forAttempt: 1), 1)
        XCTAssertEqual(RetryPolicy.backoff(forAttempt: 2), 2)
        XCTAssertEqual(RetryPolicy.backoff(forAttempt: 3), 4)
        XCTAssertEqual(RetryPolicy.backoff(forAttempt: 0), 1)
    }
}

final class DetectionRulesCodableTests: XCTestCase {
    func testRoundTrip() throws {
        let rules = RadioDetectionRules.default
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(RadioDetectionRules.self, from: data)
        XCTAssertEqual(decoded, rules)
    }

    func testMissingKeysFilledWithDefaults() throws {
        let data = Data(#"{"minimumRadioScore": 5}"#.utf8)
        let rules = try JSONDecoder().decode(RadioDetectionRules.self, from: data)
        XCTAssertEqual(rules.minimumRadioScore, 5)
        XCTAssertEqual(rules.radioGroupKeywords, RadioDetectionRules.default.radioGroupKeywords)
        XCTAssertEqual(rules.siriusKeywords, RadioDetectionRules.default.siriusKeywords)
        XCTAssertEqual(rules.excludeVideoChannels, true)
    }

    @MainActor
    func testSettingsStorePersistsRules() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        var rules = store.detectionRules
        rules.minimumRadioScore = 5
        store.detectionRules = rules
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.detectionRules.minimumRadioScore, 5)
    }

    @MainActor
    func testLiquidGlassPreferenceDefaultsOnAndPersists() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.liquidGlassEnabled)
        store.liquidGlassEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).liquidGlassEnabled)
    }

    @MainActor
    func testAppearanceKeepsExistingLightThemeUntilChangedAndPersists() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .light)
        store.appearance = .dark
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .dark)
        store.appearance = .system
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .system)
    }

    @MainActor
    func testWirelessOutputControlsPersist() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.sonosOutputControl)
        XCTAssertTrue(store.bluetoothOutputControl)
        store.sonosOutputControl = false
        store.bluetoothOutputControl = false
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.sonosOutputControl)
        XCTAssertFalse(reloaded.bluetoothOutputControl)
    }

    @MainActor
    func testCellularBufferDefaultsToSixSecondsAndPersists() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.cellularBuffer, StreamBuffer.defaultCellularDuration,
                       "Cellular gets a slightly larger reserve until the listener adjusts it")
        store.cellularBuffer = 12
        XCTAssertEqual(SettingsStore(defaults: defaults).cellularBuffer, 12)
    }

    @MainActor
    func testStoredCellularBufferOutsideTheRangeIsBroughtBackIntoIt() {
        let defaults = makeIsolatedDefaults()
        defaults.set(500.0, forKey: SettingsStore.Keys.cellularBuffer)
        XCTAssertEqual(SettingsStore(defaults: defaults).cellularBuffer, StreamBuffer.cellularRange.upperBound)
    }
}
