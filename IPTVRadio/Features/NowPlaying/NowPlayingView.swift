import SwiftUI
import AVKit

/// Full now-playing screen: artwork, controls, sleep timer, route picker.
struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showSleepTimerSheet = false
    /// Channel logo, used as the backdrop when there is no song artwork.
    @State private var stationLogo: UIImage?

    /// What fills the screen behind the player: the current song's artwork when
    /// the stream provides it, otherwise the channel logo.
    private var backdropImage: UIImage? {
        playback.nowPlayingMetadata?.artworkImage ?? stationLogo
    }

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
    }

    private func content(for station: RadioStation) -> some View {
        GeometryReader { proxy in
            // The artwork grows with the sheet but is capped against height as
            // well as width, so the controls are never squeezed off the bottom
            // of a small screen.
            // Clamped at the bottom: a GeometryReader can report a zero size on
            // an initial or transition pass, and `width - 48` would then be
            // negative — an invalid frame and an out-of-range font size.
            let artworkSize = max(120, min(proxy.size.width - 48, max(160, proxy.size.height * 0.40)))

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

                PlaybackArtwork(
                    station: station,
                    songArtwork: playback.nowPlayingMetadata?.artworkImage,
                    size: artworkSize
                )
                // Lifts the sharp artwork off the blurred backdrop behind it.
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .padding(.top, 12)

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
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .accessibilityIdentifier("nowplaying.song")
                    }
                    Text(station.name)
                        .font(playback.nowPlayingMetadata?.title == nil ? .title2.weight(.semibold) : .footnote)
                        .foregroundStyle(playback.nowPlayingMetadata?.title == nil ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("nowplaying.title")
                    if !station.groupTitle.isEmpty {
                        Text(station.groupTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(stateText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateColor)
                        .accessibilityIdentifier("nowplaying.state")
                }

                Spacer()

                controlRow

                if let diagnostics = playback.streamDiagnostics {
                    StreamDiagnosticsSummaryCard(diagnostics: diagnostics)
                }

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
            .background(NowPlayingBackdrop(image: backdropImage))
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
        HStack(spacing: 40) {
            Button {
                playback.previousStation()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Previous station")
            .accessibilityIdentifier("nowplaying.previous")

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 44))
                    .frame(width: 88, height: 88)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
            .accessibilityLabel(mainButtonLabel)
            .accessibilityIdentifier("nowplaying.toggle")

            Button {
                playback.nextStation()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Next station")
            .accessibilityIdentifier("nowplaying.next")

            Button {
                playback.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("nowplaying.stop")
        }
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

/// Full-bleed artwork behind the now playing screen.
///
/// The image is scaled to fill, blurred hard, and covered with a scrim. At that
/// blur radius it reads as colour and light rather than as a picture, which is
/// the point: the song title, controls and state text all sit on top of it and
/// have to stay legible against whatever a provider happens to serve — a dark
/// album cover one minute, a white station logo the next.
///
/// With no artwork at all it is a gradient in the app's accent, so the screen
/// looks deliberate rather than broken.
private struct NowPlayingBackdrop: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            // Also the fallback when there is nothing to show.
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.5),
                    Color.black.opacity(0.85),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Clip before blurring: a scaled-to-fill image overflows on
                    // one axis, and an unclipped blur bleeds past the screen.
                    .clipped()
                    .blur(radius: 60)
                    // A blur samples beyond its layer as transparent, so the
                    // edges fade and leave a rim. Overscaling pushes that fade
                    // off screen. (`opaque: true` would also fix it, but it
                    // renders transparent pixels black, and keyed channel logos
                    // are mostly transparent.)
                    .scaleEffect(1.15)
                    // Keyed logos being transparent means the base gradient
                    // shows through as a tint rather than a hard edge.
                    .opacity(0.9)
            }

            // Darkest top and bottom, where the title and the controls sit.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
