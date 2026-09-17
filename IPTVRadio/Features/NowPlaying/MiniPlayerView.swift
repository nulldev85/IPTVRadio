import SwiftUI
import AVKit

/// Compact mini player docked above the tab bar.
struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @State private var showNowPlaying = false

    var body: some View {
        Group {
            if let station = playback.state.station {
                HStack(spacing: 12) {
                    StationArtwork(logoURL: station.logoURL, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(stateDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if playback.state.isBusy {
                        ProgressView().controlSize(.small)
                    }

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: iconName)
                            .font(.title3)
                    }
                    .accessibilityLabel(iconName == "play.fill" ? "Play" : iconName == "pause.fill" ? "Pause" : "Retry")
                    .accessibilityIdentifier("miniplayer.toggle")

                    Button {
                        playback.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Stop")
                    .accessibilityIdentifier("miniplayer.stop")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
                .contentShape(Rectangle())
                .onTapGesture { showNowPlaying = true }
                .accessibilityIdentifier("miniplayer.open")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the now playing screen")
                .sheet(isPresented: $showNowPlaying) {
                    NowPlayingView()
                }
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
