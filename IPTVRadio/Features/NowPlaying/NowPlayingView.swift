import SwiftUI
import AVKit

/// Full now-playing screen: artwork, controls, sleep timer, route picker.
struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showSleepTimerSheet = false
    /// Channel logo, used as the backdrop when there is no song artwork.
    @State private var stationLogo: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let station = playback.state.station {
                    content(for: station)
                } else {
                    EmptyStateView(title: "Nothing playing", message: "Pick a station to start listening.")
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            // Let the artwork run under the bar instead of being cut off by it.
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        // The backdrop is always a dark, scrimmed image, so the chrome on top
        // of it is styled for dark regardless of the system appearance. One
        // line here beats hand-colouring every label, material and icon.
        .preferredColorScheme(.dark)
        // The sheet stays swipe-to-dismissable; the drag indicator plus the
        // always-visible in-body Close control (below) guarantee a reliable
        // way back that does not depend on the system navigation bar.
        .presentationDragIndicator(.visible)
        .background(AetherTheme.background.ignoresSafeArea())
    }

    private func content(for station: RadioStation) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 24) {
                // Explicit close control rendered in the view body so dismissal
                // never depends on the system navigation bar rendering.
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.headline)
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("nowplaying.close")
                    .accessibilityLabel("Close now playing screen")
                }

                // Artwork is drawn edge to edge behind this view. Its lower
                // edge fades into the solid area above the controls.
                Spacer(minLength: max(160, proxy.size.height * 0.38))

                VStack(spacing: 6) {
                    if let metadata = playback.nowPlayingMetadata,
                       metadata.title != nil || metadata.artist != nil {
                        // Current song from the stream's metadata.
                        VStack(spacing: 2) {
                            if let title = metadata.title {
                                Text(title)
                                    .font(.title3.weight(.semibold))
                                    .multilineTextAlignment(.center)
                            }
                            if let artist = metadata.artist {
                                Text(artist)
                                    .font(.subheadline)
                                    .foregroundStyle(AetherTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .accessibilityIdentifier("nowplaying.song")
                    }
                    Text(station.name)
                        .font(playback.nowPlayingMetadata?.title == nil ? .title2.weight(.semibold) : .footnote)
                        .foregroundStyle(playback.nowPlayingMetadata?.title == nil ? AetherTheme.primaryText : AetherTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("nowplaying.title")
                    if !station.groupTitle.isEmpty {
                        Text(station.groupTitle)
                            .font(.subheadline)
                            .foregroundStyle(AetherTheme.secondaryText)
                    }
                    Text(stateText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateColor)
                        .accessibilityIdentifier("nowplaying.state")
                }

                Spacer()

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
                playback.togglePlayPause()
            } label: {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 44))
                    .frame(width: 88, height: 88)
                    .background(AetherTheme.raisedSurface)
                    .clipShape(Circle())
            }
            .accessibilityLabel(mainButtonLabel)
            .accessibilityIdentifier("nowplaying.toggle")

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
        case .playing: return "pause.fill"
        case .loading: return "hourglass"
        case .failed: return "arrow.clockwise"
        default: return "play.fill"
        }
    }

    private var mainButtonLabel: String {
        switch playback.state {
        case .playing: return "Pause"
        case .loading: return "Connecting"
        case .failed: return "Retry"
        case .paused: return "Play"
        default: return "Play"
        }
    }

    private var stateText: String {
        switch playback.state {
        case .playing: return "● Live"
        case .loading: return "Connecting…"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .failed: return "Connection failed"
        case .idle: return ""
        }
    }

    private var stateColor: Color {
        switch playback.state {
        case .playing: return .green
        case .loading: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

/// Full-width artwork that gradually disappears into the dark control area.
/// The fallback is the same blue-to-black gradient as the rest of Aether.
private struct NowPlayingBackdrop: View {
    let artwork: UIImage?
    let logo: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                AetherTheme.background

                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.78)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.40), location: 0),
                                    .init(color: .clear, location: 0.20),
                                    .init(color: .clear, location: 0.42),
                                    .init(color: .black.opacity(0.65), location: 0.72),
                                    .init(color: .black, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                } else if let logo {
                    // Wordmark logos are often transparent and much wider than
                    // a square album cover. Use them as soft color rather than
                    // enlarging and cropping the mark behind the controls.
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.65)
                        .blur(radius: 55)
                        .scaleEffect(1.2)
                        .opacity(0.55)
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
        view.tintColor = .label
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
