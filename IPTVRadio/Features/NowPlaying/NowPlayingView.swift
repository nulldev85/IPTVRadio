import SwiftUI
import AVKit

/// Full now-playing screen: artwork, controls, sleep timer, route picker.
struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var playback: PlaybackEngine

    @State private var showSleepTimerSheet = false
    /// Channel logo, used as the backdrop when there is no song artwork.
    @State private var stationLogo: UIImage?

    var body: some View {
        Group {
            if let station = playback.state.station {
                content(for: station)
            } else {
                EmptyStateView(title: "Nothing playing", message: "Pick a station to start listening.")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .background(AetherTheme.background.ignoresSafeArea())
    }

    private func content(for station: RadioStation) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                VinylRecordView(
                    artwork: playback.nowPlayingMetadata?.artworkImage ?? stationLogo,
                    isSpinning: playback.state.isPlaying && scenePhase == .active && !reduceMotion
                )
                .frame(width: recordSize(in: proxy.size), height: recordSize(in: proxy.size))
                .shadow(color: .black.opacity(0.6), radius: 28, y: 18)

                Spacer(minLength: 24)

                if let metadata = playback.nowPlayingMetadata,
                   metadata.title != nil || metadata.artist != nil {
                    VStack(spacing: 4) {
                        if let title = metadata.title {
                            Text(title)
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("nowplaying.songTitle")
                        }
                        if let artist = metadata.artist {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundStyle(AetherTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("nowplaying.artist")
                        }
                    }
                    .accessibilityIdentifier("nowplaying.song")
                }

                Spacer(minLength: 20)

                controlRow

                HStack(spacing: 28) {
                    SleepTimerButton(showSheet: $showSleepTimerSheet)
                    RoutePickerButton()
                    Button {
                        playback.retry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                    }
                    .accessibilityLabel("Retry connection")
                    .accessibilityIdentifier("nowplaying.retry")
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NowPlayingBackdrop(
                artwork: playback.nowPlayingMetadata?.artworkImage,
                logo: stationLogo
            ))
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
        }
        .task(id: station.id) {
            // The channel logo backs the screen when the stream carries no
            // song artwork.
            stationLogo = nil
            guard let url = station.logoURL else { return }
            stationLogo = await ArtworkCache.shared.image(for: url)
        }
    }

    private func recordSize(in size: CGSize) -> CGFloat {
        min(size.width - 48, size.height * 0.49)
    }

    private var controlRow: some View {
        HStack(spacing: 28) {
            Button {
                playback.previousStation()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .frame(width: 56, height: 88)
            }
            .accessibilityLabel("Previous station")
            .accessibilityIdentifier("nowplaying.previous")

            Button {
                if mainButtonIsStop {
                    playback.stop()
                    dismiss()
                } else {
                    playback.togglePlayPause()
                }
            } label: {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 44))
                    .frame(width: 88, height: 88)
            }
            .accessibilityLabel(mainButtonLabel)
            .accessibilityIdentifier(mainButtonIsStop ? "nowplaying.stop" : "nowplaying.toggle")

            Button {
                playback.nextStation()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .frame(width: 56, height: 88)
            }
            .accessibilityLabel("Next station")
            .accessibilityIdentifier("nowplaying.next")
        }
        .frame(maxWidth: .infinity)
    }

    private var mainButtonIcon: String {
        switch playback.state {
        case .playing, .loading: return "stop.fill"
        case .failed: return "arrow.clockwise"
        default: return "play.fill"
        }
    }

    private var mainButtonLabel: String {
        switch playback.state {
        case .playing, .loading: return "Stop"
        case .failed: return "Retry"
        case .paused: return "Play"
        default: return "Play"
        }
    }

    private var mainButtonIsStop: Bool {
        switch playback.state {
        case .playing, .loading: return true
        default: return false
        }
    }

}

/// Cover art supplies atmosphere behind the record without competing with its
/// grooves, song text, or controls. A channel logo is the fallback artwork.
private struct NowPlayingBackdrop: View {
    let artwork: UIImage?
    let logo: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AetherTheme.background

                if let image = artwork ?? logo {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 38)
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.64), .black.opacity(0.55), .black.opacity(0.84)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

}

/// Sleep timer trigger button with active-timer indicator.
struct SleepTimerButton: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Binding var showSheet: Bool

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: playback.sleepTimerDeadline == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.title3)
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityIdentifier("nowplaying.sleepTimer")
    }
}

/// System AirPlay/Bluetooth route picker.
struct RoutePickerButton: View {
    var body: some View {
        AVRoutePickerViewRepresentable()
            .frame(width: 28, height: 28)
            .accessibilityLabel("Audio output route")
    }
}

struct AVRoutePickerViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(AetherTheme.mutedIcon)
        view.activeTintColor = UIColor(AetherTheme.secondaryText)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Sleep timer options sheet.
struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    private let options: [Double] = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.self) { minutes in
                        Button {
                            playback.startSleepTimer(minutes: minutes)
                            dismiss()
                        } label: {
                            Text("\(Int(minutes)) minutes")
                        }
                    }
                }
                if playback.sleepTimerDeadline != nil {
                    Section {
                        Button(role: .destructive) {
                            playback.cancelSleepTimer()
                            dismiss()
                        } label: {
                            Text("Cancel sleep timer")
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
