import SwiftUI
import AVKit

/// Full now-playing screen: artwork, controls, sleep timer, route picker.
struct NowPlayingView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showSleepTimerSheet = false
    @State private var showDiagnostics = false

    var body: some View {
        // No NavigationStack, toolbar or nav bar: the Close/Diagnostics bar
        // below is a plain view pinned via safeAreaInset, so dismissal never
        // depends on system chrome that could fail to render or scroll away.
        Group {
            if let station = playback.state.station {
                content(for: station)
            } else {
                EmptyStateView(title: "Nothing playing", message: "Pick a station to start listening.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        // safeAreaInset composites topBar as a sibling layer above the main
        // content and pushes that content down to make room for it, so no
        // artwork, gradient, loading state or future overlay can ever be
        // drawn on top of it. It is present in every branch above, in every
        // playback state, unconditionally.
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        // The sheet stays swipe-to-dismissable; the drag indicator plus the
        // always-visible topBar Close control guarantee a reliable way back
        // that does not depend on the system navigation bar.
        .presentationDragIndicator(.visible)
    }

    /// Always-visible Close/Diagnostics bar. Rendered via safeAreaInset (see
    /// `body`) so it sits above artwork/gradients/loading views with a high
    /// zIndex as belt-and-suspenders, and naturally respects the top safe
    /// area since it is not wrapped in `.ignoresSafeArea()`.
    private var topBar: some View {
        HStack {
            Text("Now Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("nowplaying.header")

            Spacer()

            Button {
                showDiagnostics = true
            } label: {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Playback diagnostics")
            .accessibilityIdentifier("nowplaying.diagnostics")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Close now playing screen")
            .accessibilityIdentifier("nowplaying.close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .zIndex(1000)
        .sheet(isPresented: $showDiagnostics) {
            PlaybackDiagnosticsSheet()
        }
    }

    private func content(for station: RadioStation) -> some View {
        VStack(spacing: 24) {
            StationArtwork(logoURL: station.logoURL, size: 220)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(station.name)
                    .font(.title2.weight(.semibold))
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
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
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
