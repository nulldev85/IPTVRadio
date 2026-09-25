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

/// Abstraction over artwork fetching (injectable for deterministic tests).
protocol ArtworkDataLoading: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionArtworkLoader: ArtworkDataLoading {
    let session: URLSession

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
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
    private let artworkLoader: ArtworkDataLoading
    private let metadataLock = NSLock()
    private var metadata: RadioStation?
    /// Current song info from the stream (ID3), when available.
    private var songMetadata: NowPlayingMetadata?
    private(set) var lastArtworkOutcome: ArtworkOutcome = .none
    private(set) var lastAppliedArtworkStationID: String?
    /// Remote commands are process-global; register only once.
    private static let registrationLock = NSLock()
    private static var registered = false

    weak var commandDelegate: (any NowPlayingCommandDelegate)?

    convenience init(artworkSession: URLSession = .shared) {
        self.init(artworkLoader: URLSessionArtworkLoader(session: artworkSession))
    }

    init(artworkLoader: ArtworkDataLoading) {
        self.artworkLoader = artworkLoader
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
        let stationChanged = metadata?.id != station.id
        metadata = station
        if stationChanged {
            // Station changed: previous artwork and song info are stale.
            lastAppliedArtworkStationID = nil
            lastArtworkOutcome = .none
            songMetadata = nil
        }
        let song = songMetadata
        metadataLock.unlock()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song?.title ?? station.name,
            MPMediaItemPropertyArtist: song?.artist ?? (station.groupTitle.isEmpty ? "Live Radio" : station.groupTitle),
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: (state.isPlaying && !buffering) ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: 1,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: 1,
        ]
        if song != nil {
            info[MPMediaItemPropertyAlbumTitle] = station.name
        }
        if let image = song?.artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else if !stationChanged,
                  let existing = infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            // This rebuilds the dictionary from scratch, so artwork already
            // applied for this station — the channel logo, which arrives later
            // over the network — would be dropped by any unrelated update such
            // as a pause or a route change. Carried over while the station is
            // the same; a station change must not inherit the old logo.
            info[MPMediaItemPropertyArtwork] = existing
        }
        infoCenter.nowPlayingInfo = info
    }

    /// Applies current-song info (ID3) so the lock screen and Control Center
    /// show the song title, artist and artwork instead of the channel logo.
    func applySongMetadata(_ song: NowPlayingMetadata, station: RadioStation) {
        metadataLock.lock()
        songMetadata = song
        let stationChanged = metadata?.id != station.id
        metadata = station
        if stationChanged {
            lastAppliedArtworkStationID = nil
            lastArtworkOutcome = .none
        }
        if song.artworkImage != nil {
            lastAppliedArtworkStationID = station.id
            lastArtworkOutcome = .applied
        }
        metadataLock.unlock()

        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = song.title ?? station.name
        info[MPMediaItemPropertyArtist] = song.artist ?? (station.groupTitle.isEmpty ? "Live Radio" : station.groupTitle)
        info[MPMediaItemPropertyAlbumTitle] = station.name
        if let image = song.artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        infoCenter.nowPlayingInfo = info
    }

    /// Return to the station name/logo when a live source stops reporting a
    /// current song, such as during a commercial break.
    func clearSongMetadata(state: PlaybackState) {
        guard let station = state.station else { return }
        metadataLock.lock()
        guard metadata?.id == station.id else {
            metadataLock.unlock()
            return
        }
        songMetadata = nil
        metadataLock.unlock()
        infoCenter.nowPlayingInfo = nil
        update(state: state)
        loadArtwork(for: station)
    }

    private func applyArtwork(_ image: UIImage, for station: RadioStation) {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        // Song artwork (from stream metadata) takes precedence over the
        // channel logo while a song is playing.
        guard songMetadata?.artworkImage == nil else { return }
        let item = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
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
        songMetadata = nil
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
    /// only if the station is still the active one. Never blocks playback or
    /// the main actor (all shared state is lock-guarded).
    func loadArtwork(for station: RadioStation) {
        guard let url = station.logoURL else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await self.artworkLoader.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = UIImage(data: data) else {
                    self.setOutcome(.failed)
                    return
                }
                // Key out uniform logo backgrounds so artwork looks clean on
                // the dark lock screen.
                let processed = LogoBackgroundKeyer.keyed(image)
                // The station may have changed while the artwork was loading.
                guard self.currentMetadata?.id == station.id else {
                    self.setOutcome(.skippedForStaleStation)
                    return
                }
                self.applyArtwork(processed, for: station)
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
