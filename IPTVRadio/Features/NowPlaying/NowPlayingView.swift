import SwiftUI
import AVKit

/// Full now-playing screen: artwork, controls, sleep timer, route picker.
struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showSleepTimerSheet = false
    /// Channel logo, shown as the artwork when there is no song cover.
    @State private var stationLogo: UIImage?

    /// Height kept clear below the artwork for the song text, the transport,
    /// the utilities row and the diagnostics line. The artwork takes whatever
    /// is left, so on a small screen it gives way instead of pushing the
    /// controls off the bottom.
    private static let controlsReserve: CGFloat = 300

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
        // A sheet does not inherit the app's locked appearance, so it is set
        // here too: everything on this screen is drawn for a dark page.
        .preferredColorScheme(.dark)
        // The sheet stays swipe-to-dismissable; the drag indicator plus the
        // always-visible in-body Close control guarantee a reliable way back.
        .presentationDragIndicator(.visible)
    }

    private func content(for station: RadioStation) -> some View {
        GeometryReader { proxy in
            // Tall artwork, low controls. The artwork takes most of the screen
            // and dissolves into the page along its bottom edge, which puts the
            // transport down where a thumb already is. Floored because a
            // GeometryReader can report a zero size on a transition pass, and
            // capped so the block below always has room.
            let artworkHeight = max(
                220,
                min(proxy.size.height * 0.62, proxy.size.height - Self.controlsReserve)
            )

            VStack(spacing: 0) {
                artwork(width: max(1, proxy.size.width), height: artworkHeight)

                // Absorbs the slack on a tall screen, so the controls sit at
                // the bottom rather than floating under the artwork.
                Spacer(minLength: 0)

                VStack(spacing: 20) {
                    songText(for: station)
                    controlRow
                    utilitiesRow

                    if let diagnostics = playback.streamDiagnostics {
                        StreamDiagnosticsSummaryCard(diagnostics: diagnostics)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Flat page. The artwork fades into exactly this colour, so there
            // is no seam to see and no blurred copy of the cover competing with
            // the cover itself.
            .background(Color.appBackground.ignoresSafeArea())
            // Dismissal must never depend on the system navigation bar
            // rendering, and the artwork fills the top of the screen — so the
            // close control floats over it instead of sitting above it.
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.appTextPrimary, Color.black.opacity(0.4))
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

    /// Song, station and connection state, in that order of prominence.
    @ViewBuilder
    private func songText(for station: RadioStation) -> some View {
        VStack(spacing: 6) {
            if let metadata = playback.nowPlayingMetadata,
               metadata.title != nil || metadata.artist != nil {
                // The current song, from whichever source had it.
                VStack(spacing: 3) {
                    if let title = metadata.title {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.appTextPrimary)
                            .multilineTextAlignment(.center)
                    }
                    if let artist = metadata.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityIdentifier("nowplaying.song")
            }
            Text(station.name)
                .font(playback.nowPlayingMetadata?.title == nil ? .title2.weight(.semibold) : .footnote)
                .foregroundStyle(playback.nowPlayingMetadata?.title == nil ? Color.appTextPrimary : Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("nowplaying.title")
            Text(stateText)
                .font(.caption2.weight(.medium))
                .tracking(0.6)
                .foregroundStyle(stateColor)
                .accessibilityIdentifier("nowplaying.state")
        }
    }

    /// Utilities, deliberately a step quieter than the transport above them:
    /// same size, secondary colour, no plates.
    private var utilitiesRow: some View {
        HStack(spacing: 34) {
            SleepTimerButton(showSheet: $showSleepTimerSheet)
            RoutePickerButton()
            Button {
                playback.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
            }
            .accessibilityLabel("Retry connection")
            .accessibilityIdentifier("nowplaying.retry")
        }
        .foregroundStyle(Color.appTextSecondary)
    }

    /// The artwork, full width, bleeding off the top of the screen and
    /// dissolving into the page along its bottom edge.
    ///
    /// Scaled to fill and clipped rather than fitted: a cover whose aspect
    /// ratio does not match the frame should crop like a photograph instead of
    /// leaving bars down the sides. The gradient is deliberately long — over a
    /// third of the artwork's height, in four stops — because a short one reads
    /// as a dark band across the picture, while this reads as the image running
    /// out. It ends on the page's own colour, so there is no seam at all.
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
                // Nothing to show yet: a grey plate rather than a void, so the
                // screen looks deliberate while the artwork is still loading.
                LinearGradient(
                    colors: [Color.appElevated, Color.appSurface],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.appTextTertiary)
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .appBackground.opacity(0), location: 0),
                    .init(color: .appBackground.opacity(0.45), location: 0.45),
                    .init(color: .appBackground.opacity(0.88), location: 0.78),
                    .init(color: .appBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(1, height * 0.38))
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
        .foregroundStyle(Color.appTextPrimary)
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
        case .playing: return .appLive
        case .loading: return .appTextSecondary
        case .failed: return .appAlert
        default: return .appTextSecondary
        }
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
        view.tintColor = .appTextSecondary
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
                                .foregroundStyle(Color.appTextPrimary)
                        }
                    }
                }
                .listRowBackground(Color.appSurface)
                .listRowSeparatorTint(Color.appHairline)
                if playback.sleepTimerDeadline != nil {
                    Section {
                        Button(role: .destructive) {
                            playback.cancelSleepTimer()
                            dismiss()
                        } label: {
                            Text("Cancel sleep timer")
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .appScrollBackground()
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
