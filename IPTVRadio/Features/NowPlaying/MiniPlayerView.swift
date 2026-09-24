import SwiftUI
import AVKit

/// Compact mini player shown above the tab bar while a station is loaded.
/// Owns no presentation state: opening the full player is delegated upward.
struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackEngine

    let onOpen: () -> Void

    var body: some View {
        Group {
            if let station = playback.state.station {
                HStack(spacing: 12) {
                    Button {
                        onOpen()
                    } label: {
                        HStack(spacing: 12) {
                            PlaybackArtwork(
                                station: station,
                                songArtwork: playback.nowPlayingMetadata?.artworkImage,
                                size: 44
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(playback.nowPlayingMetadata?.title ?? station.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.appTextPrimary)
                                    .lineLimit(1)
                                Text(playback.nowPlayingMetadata?.artist ?? stateDescription)
                                    .font(.caption2)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("miniplayer.open")
                    .accessibilityLabel("Open now playing screen")
                    .accessibilityHint("Opens the full now playing controls")

                    if playback.state.isBusy {
                        ProgressView().controlSize(.small)
                    }

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel(toggleAccessibilityLabel)
                    .accessibilityIdentifier("miniplayer.toggle")

                    Button {
                        playback.stop()
                    } label: {
                        // A step quieter and smaller than play/pause: stopping
                        // is the rarer action of the two.
                        Image(systemName: "stop.fill")
                            .font(.callout)
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Stop")
                    .accessibilityIdentifier("miniplayer.stop")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                // Flat surface, not `.bar`: the system material is translucent
                // and picks up whatever scrolls behind it. This shares its
                // colour with the tab bar below, so the two read as one dock,
                // separated from the content only by a hairline.
                .background(Color.appSurface)
                .appTopHairline()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playback.state.station?.id)
    }

    private var iconName: String {
        switch playback.state {
        case .playing: return "pause.fill"
        case .loading: return "arrow.clockwise"
        case .failed: return "arrow.clockwise"
        case .paused, .stopped: return "play.fill"
        default: return "play.fill"
        }
    }

    private var toggleAccessibilityLabel: String {
        switch playback.state {
        case .playing: return "Pause"
        case .loading: return "Retry"
        case .failed: return "Retry"
        default: return "Play"
        }
    }

    private var stateDescription: String {
        switch playback.state {
        case .playing: return "Playing live"
        case .paused: return "Paused"
        case .loading: return "Connecting…"
        case .failed: return "Connection failed — tap to retry"
        case .stopped: return "Stopped"
        case .idle: return ""
        }
    }
}
