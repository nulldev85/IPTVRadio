import SwiftUI

/// One station row with artwork, favorite toggle and live state.
struct StationRow: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var manualStations: ManualStationStore

    let station: RadioStation

    private var displayedStation: RadioStation {
        station.source == .manual ? (manualStations.station(id: station.id) ?? station) : station
    }

    var isCurrent: Bool {
        playback.state.station?.id == station.id
    }

    var body: some View {
        Button {
            // Favorites and history may hold station copies saved by older
            // app versions (with stale stream URLs). Always play the fresh
            // library copy when one is available.
            let fresh = station.source == .manual
                ? displayedStation
                : library.freshStation(matching: station)
            playback.play(fresh, in: nil)
        } label: {
            HStack(spacing: 12) {
                StationArtwork(logoURL: displayedStation.logoURL, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(AetherTheme.primaryText)
                        .lineLimit(2)
                    if !station.groupTitle.isEmpty {
                        Text(station.groupTitle)
                            .font(.caption)
                            .foregroundStyle(AetherTheme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isCurrent {
                    playbackStateBadge
                }

                Button {
                    favorites.toggle(displayedStation)
                } label: {
                    Image(systemName: favorites.isFavorite(station) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(station) ? AetherTheme.coral : AetherTheme.mutedIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorites.isFavorite(station) ? "Remove from favorites" : "Add to favorites")
                .accessibilityIdentifier("station.favorite.\(station.name)")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("station.row.\(station.name)")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this station")
    }

    @ViewBuilder
    private var playbackStateBadge: some View {
        switch playback.state {
        case .playing, .paused:
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                Text("Live")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
        case .loading:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

/// A station's channel logo.
///
/// Provider logos are background-keyed once (see `LogoBackgroundKeyer`) so they
/// sit on any theme. Nothing is drawn behind a logo that loaded: a filled
/// rounded square behind a keyed logo just restores the box the keying removed,
/// which is what made every logo look like it sat on a grey tile.
struct StationArtwork: View {
    let logoURL: URL?
    var size: CGFloat = 52

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    // Fit, not fill: provider logos are often wide wordmarks,
                    // and filling crops them into a square.
                    .aspectRatio(contentMode: .fit)
            } else if logoURL == nil || didFail {
                placeholder
            }
            // While loading, stay empty rather than flashing a grey plate.
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: logoURL) {
            // Reset first. This view keeps its position across station changes
            // (the mini player and the now playing screen both reuse it), so
            // leaving the previous station's image in place shows its logo for
            // the whole of the next station's fetch — and permanently, for a
            // station that has no logo at all and returns early below.
            image = nil
            didFail = false
            guard let logoURL else { return }
            let loaded = await ArtworkCache.shared.image(for: logoURL)
            image = loaded
            didFail = loaded == nil
        }
    }

    /// Only shown when there is no logo, or it could not be loaded.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AetherTheme.raisedSurface)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.38))
                .foregroundStyle(AetherTheme.mutedIcon)
        }
    }
}

/// Artwork used while playing: shows the current song's artwork when the
/// stream provides it, falling back to the channel logo otherwise.
/// (Channel logos remain unchanged everywhere else in the app.)
struct PlaybackArtwork: View {
    let station: RadioStation
    let songArtwork: UIImage?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let songArtwork {
                Image(uiImage: songArtwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            } else {
                StationArtwork(logoURL: station.logoURL, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Tiny in-memory artwork cache to avoid refetching logos while scrolling.
/// Channel logos are background-keyed once so they sit cleanly on the dark
/// (OLED) theme.
actor ArtworkCache {
    static let shared = ArtworkCache()
    private var cache: [URL: UIImage] = [:]
    private var failed: Set<URL> = []

    func image(for url: URL) async -> UIImage? {
        if let image = cache[url] { return image }
        if failed.contains(url) { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                failed.insert(url)
                return nil
            }
            let processed = LogoBackgroundKeyer.keyed(image)
            cache[url] = processed
            return processed
        } catch {
            failed.insert(url)
            return nil
        }
    }
}
