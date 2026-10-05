import SwiftUI

/// Public-radio discovery lives inside Radio; saved stations use the existing
/// manual station store, while previews use the normal playback engine.
struct AetherDialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var manualStations: ManualStationStore
    @EnvironmentObject private var playback: PlaybackEngine

    @State private var place = ""
    @State private var stationName = ""
    @State private var worldwide = false
    @State private var genre: DialGenre = .all
    @State private var results: [DialStation] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var busyStationID: String?
    @State private var searchError: String?
    @State private var actionError: String?
    @State private var showNowPlaying = false

    private var directory: AetherDialService {
        AetherDialService(httpClient: environment.httpClient)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    searchControls
                    resultContent
                    Link("Station directory by Radio Browser", destination: URL(string: "https://www.radio-browser.info/")!)
                        .font(.caption)
                        .foregroundStyle(AetherTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AetherTheme.background.ignoresSafeArea())
            .navigationTitle("Aether Dial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerView(onOpen: { showNowPlaying = true })
            }
            .task {
                if !hasSearched { await search() }
            }
            .sheet(isPresented: $showNowPlaying) {
                NowPlayingView()
            }
            .alert("Aether Dial", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
        .tint(AetherTheme.accent)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Go where the music is.")
                .font(AetherTheme.displayFont)
                .foregroundStyle(AetherTheme.primaryText)
            Text("Explore live stations by place and genre. Listen first, then save the ones you love to Radio.")
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("PLACE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AetherTheme.secondaryText)
                TextField("State or country", text: $place)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(AetherTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AetherTheme.border))
                    .disabled(worldwide)
                    .accessibilityIdentifier("dial.place")
                Text(worldwide
                     ? "Searching stations around the world."
                     : place.isEmpty
                         ? "Starts in \(homeCountryName). Enter a state or country to travel."
                         : "Searches the directory's country and state listings.")
                    .font(.caption)
                    .foregroundStyle(AetherTheme.secondaryText)
            }

            Toggle("Explore worldwide", isOn: $worldwide)
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 7) {
                Text("STATION NAME")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AetherTheme.secondaryText)
                TextField("Optional", text: $stationName)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(AetherTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AetherTheme.border))
                    .accessibilityIdentifier("dial.name")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("GENRE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AetherTheme.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DialGenre.allCases) { option in
                            Button(option.title) { genre = option }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .foregroundStyle(genre == option ? AetherTheme.onAccent : AetherTheme.secondaryText)
                                .background(genre == option ? AetherTheme.accent : AetherTheme.surface,
                                            in: Capsule())
                                .overlay(Capsule().stroke(genre == option ? Color.clear : AetherTheme.border))
                                .accessibilityAddTraits(genre == option ? .isSelected : [])
                        }
                    }
                }
                .contentMargins(.trailing, 22)
            }

            Button {
                Task { await search() }
            } label: {
                HStack(spacing: 9) {
                    if isSearching { ProgressView().tint(AetherTheme.onAccent) }
                    else { Image(systemName: "magnifyingglass") }
                    Text("Explore stations")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching)
            .accessibilityIdentifier("dial.search")
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On the dial")
                        .font(AetherTheme.sectionFont)
                        .foregroundStyle(AetherTheme.primaryText)
                    if !results.isEmpty {
                        Text("\(results.count) stations")
                            .font(.caption)
                            .foregroundStyle(AetherTheme.secondaryText)
                    }
                }
                Spacer()
                if !results.isEmpty {
                    Button {
                        if let surprise = results.randomElement() {
                            Task { await preview(surprise) }
                        }
                    } label: {
                        Label("Spin", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(busyStationID != nil)
                    .accessibilityLabel("Play a surprise station")
                }
            }

            if isSearching && results.isEmpty {
                ProgressView("Finding stations…")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else if let searchError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                    Text(searchError)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await search() } }
                }
                .foregroundStyle(AetherTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if results.isEmpty {
                Text(hasSearched
                     ? "No working stations matched. Try another place, genre, or name."
                     : "Choose a place or genre to start exploring.")
                    .font(.subheadline)
                    .foregroundStyle(AetherTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(results) { station in
                        stationRow(station)
                    }
                }
            }
        }
    }

    private func stationRow(_ station: DialStation) -> some View {
        let saved = isSaved(station)
        let playing = playback.state.station?.id == "dial-\(station.id)"
        return HStack(spacing: 8) {
            Button {
                Task { await preview(station) }
            } label: {
                HStack(spacing: 12) {
                    StationArtwork(logoURL: station.logoURL, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AetherTheme.primaryText)
                            .lineLimit(2)
                        if !station.location.isEmpty {
                            Text(station.location)
                                .font(.caption)
                                .foregroundStyle(AetherTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Text(stationDetails(station))
                            .font(.caption2)
                            .foregroundStyle(AetherTheme.mutedIcon)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if busyStationID == station.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: playing ? "waveform" : "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(AetherTheme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busyStationID != nil)
            .accessibilityLabel("Listen to \(station.name)")

            Button {
                Task { await save(station) }
            } label: {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(saved ? AetherTheme.accent : AetherTheme.mutedIcon)
                    .frame(width: 42, height: 46)
            }
            .buttonStyle(.plain)
            .disabled(saved || busyStationID != nil)
            .accessibilityLabel(saved ? "Already in Radio" : "Add \(station.name) to Radio")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            AetherTheme.border.opacity(0.72)
                .frame(height: 0.5)
                .padding(.leading, 62)
        }
    }

    private func stationDetails(_ station: DialStation) -> String {
        var parts = Array(station.tags.prefix(2))
        if let codec = station.codec {
            parts.append(station.bitrate.map { "\(codec) · \($0) kbps" } ?? codec)
        }
        return parts.isEmpty ? "Live radio" : parts.joined(separator: " · ")
    }

    private func isSaved(_ station: DialStation) -> Bool {
        manualStations.entries.contains {
            $0.streamURL == station.streamURL || $0.streamURL == station.previewURL
                || $0.playbackURLs.contains(station.previewURL)
        }
    }

    private var homeCountryCode: String {
        let code = Locale.current.region?.identifier ?? "US"
        return code.count == 2 ? code.uppercased() : "US"
    }

    private var homeCountryName: String {
        Locale.current.localizedString(forRegionCode: homeCountryCode) ?? homeCountryCode
    }

    @MainActor
    private func search() async {
        guard !isSearching else { return }
        isSearching = true
        hasSearched = true
        searchError = nil
        results = []
        defer { isSearching = false }
        let query = DialQuery(
            place: worldwide ? "" : place,
            genre: genre.tag,
            name: stationName,
            worldwide: worldwide,
            homeCountryCode: homeCountryCode
        )
        do {
            results = try await directory.search(query)
        } catch {
            searchError = (error as? AetherDialError)?.errorDescription
                ?? "The radio directory could not be reached. Try again."
        }
    }

    @MainActor
    private func preview(_ station: DialStation) async {
        guard busyStationID == nil else { return }
        if playback.state.station?.id == "dial-\(station.id)" {
            if !playback.state.isPlaying { playback.togglePlayPause() }
            return
        }
        busyStationID = station.id
        defer { busyStationID = nil }
        do {
            let urls = try await ManualPlaylistResolver(httpClient: environment.httpClient)
                .resolve(station.previewURL)
            let playable = station.previewStation(playbackURLs: urls)
            playback.play(playable, in: [playable])
            let service = directory
            Task { await service.registerClick(stationID: station.id) }
        } catch {
            actionError = "This stream could not be opened. Try another station."
        }
    }

    @MainActor
    private func save(_ station: DialStation) async {
        guard busyStationID == nil, !isSaved(station) else { return }
        busyStationID = station.id
        defer { busyStationID = nil }
        do {
            _ = try await manualStations.save(
                ManualStationInput(
                    name: station.name,
                    streamURL: station.streamURL.absoluteString,
                    logoURL: station.logoURL?.absoluteString ?? "",
                    directoryStationID: station.id
                ),
                httpClient: environment.httpClient
            )
        } catch {
            actionError = (error as? ManualStationError)?.errorDescription
                ?? "The station could not be added. Try again."
        }
    }
}

private enum DialGenre: String, CaseIterable, Identifiable {
    case all, rock, pop, jazz, talk, electronic, classical, country, hipHop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .rock: "Rock"
        case .pop: "Pop"
        case .jazz: "Jazz"
        case .talk: "Talk"
        case .electronic: "Electronic"
        case .classical: "Classical"
        case .country: "Country"
        case .hipHop: "Hip-Hop"
        }
    }

    var tag: String? {
        if self == .all { return nil }
        return self == .hipHop ? "hip hop" : title.lowercased()
    }
}
