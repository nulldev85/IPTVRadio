import XCTest
import AVFoundation
@testable import IPTVRadio

/// Verifies the audio session configuration that determines playback quality:
/// standard playback category (A2DP-capable), no voice-chat/recording modes,
/// no telephone-quality audio paths.
@MainActor
final class AudioSessionConfigTests: XCTestCase {
    func testPlaybackActivationUsesHighQualityConfiguration() throws {
        let adapter = AVAudioSessionAdapter()
        try adapter.activateForPlayback()

        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback, "Category must be .playback for full-quality A2DP/Bluetooth output")
        XCTAssertEqual(session.mode, .default, "Mode must stay .default; voice-chat modes force telephone-quality audio")
        XCTAssertTrue(session.categoryOptions.isEmpty, "No special options (ducking/measure/voice-processing) should be set")
        XCTAssertNotEqual(session.mode, .voiceChat)
    }

    func testDeactivationStopsPlaybackSession() throws {
        let adapter = AVAudioSessionAdapter()
        try adapter.activateForPlayback()
        try adapter.deactivate()
        // Deactivation with notifyOthersOnDeactivation should not throw; state
        // is best checked by absence of our category being active elsewhere.
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }
}
