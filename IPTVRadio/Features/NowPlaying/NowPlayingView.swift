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
        // No navigation bar: it reserves space at the top of the sheet, and the
        // artwork is meant to reach the very edge of the screen. The in-body
        // close control and the sheet's drag indicator are what dismiss this,
        // so nothing is lost by dropping the bar.
        Group {
            if let station = playback.state.station {
                content(for: station)
            } else {
                EmptyStateView(title: "Nothing playing", message: "Pick a station to start listening.")
            }
        }
        // The backdrop is always a dark, scrimmed image, so the chrome on top
        // of it is styled for dark regardless of the system appearance. One
        // line here beats hand-colouring every label, material and icon.
        .preferredColorScheme(.dark)
        // The sheet stays swipe-to-dismissable; the drag indicator plus the
        // always-visible in-body Close control guarantee a reliable way back.
        .presentationDragIndicator(.visible)
    }

    private func content(for station: RadioStation) -> some View {
        GeometryReader { proxy in
            // Roughly square and the full width of the screen, capped against
            // height so the controls below are never pushed off a short one.
            // Clamped at the bottom because a GeometryReader can report a zero
            // size on an initial or transition pass, and a zero-height frame
            // would collapse the artwork entirely.
            let artworkHeight = max(200, min(proxy.size.width, proxy.size.height * 0.55))

            VStack(spacing: 0) {
                artwork(width: max(1, proxy.size.width), height: artworkHeight)

                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        if let metadata = playback.nowPlayingMetadata,
                           metadata.title != nil || metadata.artist != nil {
                            // The current song, from whichever source had it.
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
                        Text(stateText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(stateColor)
                            .accessibilityIdentifier("nowplaying.state")
                    }

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

                    if let diagnostics = playback.streamDiagnostics {
                        StreamDiagnosticsSummaryCard(diagnostics: diagnostics)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(NowPlayingBackdrop(image: backdropImage))
            // Dismissal must never depend on the system navigation bar
            // rendering, and the artwork now fills the top of the screen — so
            // the close control floats over it instead of sitting above it.
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .padding(.trailing, 18)
                .padding(.top, 14)
                .accessibilityIdentifier("nowplaying.close")
                .accessibilityLabel("Close now playing screen")
            }
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
        }
        .task(id: station.id) {
            // The channel logo stands in for artwork whenever no source has
            // supplied a cover for the current song.
            stationLogo = nil
            guard let url = station.logoURL else { return }
            stationLogo = await ArtworkCache.shared.image(for: url)
        }
    }

    /// The artwork, full width and bleeding off the top of the screen.
    ///
    /// Scaled to fill and clipped rather than fitted: a cover whose aspect
    /// ratio does not match the frame should crop like a photograph instead of
    /// leaving bars down the sides. The gradient along the bottom edge melts
    /// the image into the page so there is no hard seam between them.
    @ViewBuilder
    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let image = playback.nowPlayingMetadata?.artworkImage ?? stationLogo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                // Nothing to show yet: a tint rather than a void, so the screen
                // looks deliberate while the artwork is still loading.
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.35), Color.black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width, height: height)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(1, height * 0.3))
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
        .ignoresSafeArea(edges: .top)
    }

    /// Transport: previous station, play/pause, next station.
    ///
    /// Three controls, drawn as plain solid glyphs with no plate behind them.
    /// Stop is deliberately absent — the mini player carries it, and a live
    /// radio screen reads better without a fourth control competing with the
    /// play button.
    private var controlRow: some View {
        HStack(spacing: 52) {
            Button {
                playback.previousStation()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32, weight: .semibold))
            }
            .accessibilityLabel("Previous station")
            .accessibilityIdentifier("nowplaying.previous")

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 46, weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(mainButtonLabel)
            .accessibilityIdentifier("nowplaying.toggle")

            Button {
                playback.nextStation()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32, weight: .semibold))
            }
            .accessibilityLabel("Next station")
            .accessibilityIdentifier("nowplaying.next")
        }
        .foregroundStyle(.white)
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
