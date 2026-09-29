import XCTest
@testable import IPTVRadio

final class StreamBufferTests: XCTestCase {
    func testWiFiUsesTheStandardBufferWhateverTheCellularSetting() {
        let buffer = StreamBuffer.forConnection(isCellular: false, isExpensive: false, cellularSetting: 20)
        XCTAssertEqual(buffer, .standard)
        XCTAssertEqual(buffer.duration, StreamBuffer.standardDuration)
        XCTAssertFalse(buffer.isCellular)
    }

    func testCellularUsesTheListenersSetting() {
        let buffer = StreamBuffer.forConnection(isCellular: true, isExpensive: true, cellularSetting: 12)
        XCTAssertEqual(buffer, StreamBuffer(duration: 12, isCellular: true))
    }

    func testPersonalHotspotCountsAsCellular() {
        // A hotspot reaches the device as Wi-Fi; only the expensive flag
        // gives it away.
        let buffer = StreamBuffer.forConnection(isCellular: false, isExpensive: true, cellularSetting: 9)
        XCTAssertEqual(buffer, StreamBuffer(duration: 9, isCellular: true))
    }

    func testCellularSettingIsKeptWithinTheOfferedRange() {
        func duration(_ setting: TimeInterval) -> TimeInterval {
            StreamBuffer.forConnection(isCellular: true, isExpensive: true, cellularSetting: setting).duration
        }
        XCTAssertEqual(duration(1), StreamBuffer.cellularRange.lowerBound)
        XCTAssertEqual(duration(600), StreamBuffer.cellularRange.upperBound)
        XCTAssertEqual(duration(.nan), StreamBuffer.standardDuration)
        XCTAssertEqual(duration(.infinity), StreamBuffer.standardDuration)
    }

    func testOnlyBufferBeyondTheStandardExtendsTimeouts() {
        XCTAssertEqual(StreamBuffer.standard.extraFillTime, 0)
        XCTAssertEqual(StreamBuffer(duration: StreamBuffer.standardDuration, isCellular: true).extraFillTime, 0)
        XCTAssertEqual(StreamBuffer(duration: 10, isCellular: true).extraFillTime, 10 - StreamBuffer.standardDuration)
    }
}
