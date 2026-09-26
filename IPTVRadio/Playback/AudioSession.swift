import Foundation
import AVFoundation

/// The audio session, behind a seam so tests never touch the real one.
///
/// Activation matters more than it looks: the system deactivates the
/// session for an interruption, and resuming playback without
/// reactivating it renders silence while the player still reports itself
/// playing — so nothing detects the fault and the station appears to die
/// after every phone call.
protocol AudioSessionControlling: AnyObject {
    func activateForPlayback() throws
    func deactivate() throws
}

final class AVAudioSessionAdapter: AudioSessionControlling {
    func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try session.setActive(true, options: [])
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
