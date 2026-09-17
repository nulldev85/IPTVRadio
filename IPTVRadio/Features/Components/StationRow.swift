import SwiftUI

/// One station row with artwork, favorite toggle and live state.
struct StationRow: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var favorites: FavoritesStore

    let station: RadioStation

    var isCurrent: Bool {
        playback.state.station?.id == station.id
    }

    var body: some View {
        Button {
            playback.play(station, in: nil)
        } label: {
            HStack(spacing: 12) {
                StationArtwork(logoURL: station.logoURL, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !station.groupTitle.isEmpty {
                        Text(station.groupTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isCurrent {
                    playbackStateBadge
                }

                Button {
                    favorites.toggle(station)
                } label: {
                    Image(systemName: favorites.isFavorite(station) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(station) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorites.isFavorite(station) ? "Remove from favorites" : "Add to favorites")
                .accessibilityIdentifier("station.favorite.\(station.name)")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Async artwork with graceful fallback.
struct StationArtwork: View {
    let logoURL: URL?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
            if let logoURL {
                AsyncArtworkImage(url: logoURL)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AsyncArtworkImage: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .task(id: url) {
            image = await ArtworkCache.shared.image(for: url)
        }
    }
}

/// Tiny in-memory artwork cache to avoid refetching logos while scrolling.
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
            cache[url] = image
            return image
        } catch {
            failed.insert(url)
            return nil
        }
    }
}
