import Foundation
import MediaPlayer
import UIKit

/// Delegate invoked from MPRemoteCommandCenter handlers (always on the main actor).
@MainActor
protocol NowPlayingCommandDelegate: AnyObject {
    func handle(command: NowPlayingCommand)
}

enum NowPlayingCommand {
    case play, pause, toggle, stop, next, previous
}

/// Owns lock-screen/Control Center integration: remote commands and
/// now-playing metadata (title, artist, artwork, live flag).
final class NowPlayingManager {
    /// Tracks the outcome of the most recent artwork load attempt so tests
    /// can verify behavior without depending on MPNowPlayingInfoCenter
    /// round-tripping artwork through its info dictionary.
    enum ArtworkOutcome: Equatable {
        case none
        case applied
        case skippedForStaleStation
        case failed
    }

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let artworkSession: URLSession
    private let metadataLock = NSLock()
    private var metadata: RadioStation?
    private(set) var lastArtworkOutcome: ArtworkOutcome = .none
    private(set) var lastAppliedArtworkStationID: String?
    /// Remote commands are process-global; register only once.
    private static let registrationLock = NSLock()
    private static var registered = false

    weak var commandDelegate: (any NowPlayingCommandDelegate)?

    init(artworkSession: URLSession = .shared) {
        self.artworkSession = artworkSession
        Self.registerCommandsIfNeeded(onDispatch: { [weak self] command in
            self?.commandDelegate?.handle(command: command)
        })
    }

    private static func registerCommandsIfNeeded(onDispatch dispatch: @MainActor @escaping (NowPlayingCommand) -> Void) {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard !registered else { return }
        registered = true

        let commandCenter = MPRemoteCommandCenter.shared()
        let dispatchOnMain: (NowPlayingCommand) -> Void = { command in
            Task { @MainActor in dispatch(command) }
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            dispatchOnMain(.play)
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            dispatchOnMain(.pause)
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            dispatchOnMain(.toggle)
            return .success
        }
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { _ in
            dispatchOnMain(.stop)
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            dispatchOnMain(.next)
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            dispatchOnMain(.previous)
            return .success
        }
        // Position changes and skipping are meaningless for live radio.
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    // MARK: Metadata

    func update(state: PlaybackState, buffering: Bool = false) {
        guard let station = state.station else {
            clear()
            return
        }
        metadataLock.lock()
        metadata = station
        // Station changed: previously applied artwork is stale until it loads again.
        lastAppliedArtworkStationID = nil
        lastArtworkOutcome = .none
        metadataLock.unlock()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: station.groupTitle.isEmpty ? "Live Radio" : station.groupTitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: (state.isPlaying && !buffering) ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: 1,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: 1,
        ]
        infoCenter.nowPlayingInfo = info
    }

    private func applyArtwork(_ image: UIImage, for station: RadioStation) {
        let item = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        metadataLock.lock()
        defer { metadataLock.unlock() }
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = item
        infoCenter.nowPlayingInfo = info
        lastAppliedArtworkStationID = station.id
        lastArtworkOutcome = .applied
    }

    func clear() {
        metadataLock.lock()
        metadata = nil
        lastAppliedArtworkStationID = nil
        lastArtworkOutcome = .none
        metadataLock.unlock()
        infoCenter.nowPlayingInfo = nil
    }

    var currentMetadata: RadioStation? {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        return metadata
    }

    // MARK: Artwork

    /// Loads remote artwork asynchronously and applies it to the lock screen
    /// only if the station is still the active one. Never blocks playback.
    func loadArtwork(for station: RadioStation) {
        guard let url = station.logoURL else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await self.artworkSession.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    self.setOutcome(.failed)
                    return
                }
                // The station may have changed while the artwork was loading.
                guard self.currentMetadata?.id == station.id else {
                    self.setOutcome(.skippedForStaleStation)
                    return
                }
                self.applyArtwork(image, for: station)
            } catch {
                self.setOutcome(.failed)
            }
        }
    }

    private func setOutcome(_ outcome: ArtworkOutcome) {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        lastArtworkOutcome = outcome
    }

    /// Test hook: current now-playing info dictionary.
    var nowPlayingInfoForTesting: [String: Any]? {
        infoCenter.nowPlayingInfo
    }
}
