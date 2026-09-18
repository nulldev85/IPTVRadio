import Foundation

/// Outcome of a library refresh, used to drive distinct UI states.
enum LibraryRefreshResult: Equatable {
    case success(LibrarySnapshot)
    case successFromCache(LibrarySnapshot)
    case offline(LibrarySnapshot?)
    case expired
    case failure(String)
}

/// Derives alternate stream formats for playlist entries that follow the
/// Xtream live-URL pattern (`.../live/{user}/{pass}/{id}.{ts|m3u8}`), so the
/// stream-format preference and automatic runtime fallback also work for
/// stations imported from an M3U playlist. Other URLs are left untouched.
enum PlaylistStreamFormats {
    static func candidates(for url: URL, preference: StreamFormatPreference) -> [URL] {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return [url]
        }
        let path = url.path.lowercased()
        guard url.pathComponents.contains("live"),
              url.pathComponents.count >= 5,
              path.hasSuffix(".ts") || path.hasSuffix(".m3u8") else {
            return [url]
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [url]
        }
        let originalPath = components.path
        let siblingPath: String
        let originalIsTS: Bool
        if originalPath.lowercased().hasSuffix(".m3u8") {
            siblingPath = String(originalPath.dropLast(".m3u8".count)) + ".ts"
            originalIsTS = false
        } else {
            siblingPath = String(originalPath.dropLast(".ts".count)) + ".m3u8"
            originalIsTS = true
        }
        components.path = siblingPath
        guard let sibling = components.url, sibling != url else {
            return [url]
        }

        // Keep the playlist's URL as primary when it is already the preferred
        // format; otherwise try the preferred format first (with fallback).
        let originalIsPreferred = (preference == .automatic && originalIsTS)
            || (preference == .hlsFirst && !originalIsTS)
        return originalIsPreferred ? [url, sibling] : [sibling, url]
    }
}

/// Orchestrates fetching provider data, running detection, and caching.
@MainActor
final class LibraryService: ObservableObject {
    private let cache: StationCache
    private let redactor: Redactor

    init(cache: StationCache, redactor: Redactor = Redactor(secrets: [])) {
        self.cache = cache
        self.redactor = redactor
    }

    // MARK: Xtream fetch

    func refresh(
        credentials: XtreamCredentials,
        http: HTTPClient,
        rules: RadioDetectionRules,
        formatPreference: StreamFormatPreference = .automatic
    ) async -> LibraryRefreshResult {
        do {
            let client = try XtreamClient(credentials: credentials, http: http)
            let session = try await client.authenticate()
            if session.isExpired {
                return .expired
            }

            let rawCategories = try await client.categories()
            let streams = try await client.liveStreams()
            guard !streams.isEmpty else {
                return .failure(ProviderError.emptyPlaylist.errorDescription ?? "No channels found.")
            }

            let categoriesByID = Dictionary(
                uniqueKeysWithValues: rawCategories.map { ($0.categoryID, ChannelCategory(id: $0.categoryID, name: $0.categoryName)) }
            )

            // Prefer the protocol that successfully served the API calls, and
            // prefer the provider's original stream over any transcoded variant.
            //
            // Audio quality note: Xtream panels commonly transcode the `.m3u8`
            // (HLS) endpoint to a low-bitrate audio rendition while the `.ts`
            // endpoint carries the original stream. Most IPTV players use the
            // original `.ts` format, so it is tried first (configurable) with
            // the other format as an automatic runtime fallback.
            let orderedFormats: [String] = formatPreference == .hlsFirst ? ["m3u8", "ts"] : ["ts", "m3u8"]
            var rawChannels: [RawChannel] = streams.map { stream in
                var candidates: [URL] = []

                // 1) Provider-declared direct source (HTTPS preferred, plain
                //    HTTP kept as a fallback for hosts without TLS).
                if let directString = stream.directSource, !directString.isEmpty,
                   let direct = Lenient.url(directString), isPlayable(direct) {
                    let upgraded = upgradeToHTTPSIfPossible(direct, base: client.baseURL)
                    candidates.append(upgraded)
                    if upgraded != direct {
                        candidates.append(direct)
                    }
                }

                // 2) Native format first, compatibility format as fallback.
                for format in orderedFormats {
                    candidates.append(client.streamURL(streamID: stream.streamID, format: format))
                }

                var seen = Set<String>()
                let unique = candidates.filter { seen.insert($0.absoluteString).inserted }
                let primary = unique.first ?? client.streamURL(streamID: stream.streamID)
                // Detection always sees the HLS URL, independent of the
                // format preference, so radio classification stays stable.
                let analysisURL = client.streamURL(streamID: stream.streamID, format: "m3u8")

                let group = categoriesByID[stream.categoryID ?? ""]?.name ?? ""
                return RawChannel(
                    name: stream.name,
                    url: primary,
                    group: group,
                    logoURL: Lenient.url(stream.streamIcon),
                    tvgID: stream.epgChannelID,
                    source: .xtream,
                    categoryID: stream.categoryID,
                    alternativeURLs: Array(unique.dropFirst()),
                    analysisURL: analysisURL
                )
            }

            let detector = RadioStationDetector(rules: rules)
            let snapshot = detector.buildSnapshot(channels: rawChannels, categoriesByID: categoriesByID)
            rawChannels = []
            cache.store(snapshot)
            return .success(snapshot)
        } catch let error as ProviderError {
            switch error {
            case .unauthorized:
                return .failure(error.errorDescription ?? "Sign-in failed.")
            case .networkUnreachable, .timedOut, .serverError, .malformedResponse:
                if let cached = cache.load() {
                    return .offline(cached.snapshot)
                }
                return .failure(error.errorDescription ?? "Network problem.")
            default:
                return .failure(error.errorDescription ?? "Unexpected problem.")
            }
        } catch {
            return .failure("Something went wrong while loading your channels.")
        }
    }

    // MARK: M3U fetch

    func refresh(
        credentials: M3UPlaylistCredentials,
        http: HTTPClient,
        rules: RadioDetectionRules,
        formatPreference: StreamFormatPreference = .automatic
    ) async -> LibraryRefreshResult {
        do {
            let client = M3UClient(http: http)
            let text = try await client.fetchPlaylistText(url: credentials.url)
            let items = M3UParser.parse(text)
            guard !items.isEmpty else {
                return .failure(ProviderError.malformedResponse("Playlist was empty or malformed.").errorDescription ?? "Playlist malformed.")
            }
            let channels = items.map { item in
                let formatCandidates = PlaylistStreamFormats.candidates(
                    for: item.url,
                    preference: formatPreference
                )
                return RawChannel(
                    name: item.name,
                    url: formatCandidates.first ?? item.url,
                    group: item.groupTitle,
                    logoURL: item.logoURL,
                    tvgID: item.tvgID,
                    source: .m3u,
                    alternativeURLs: Array(formatCandidates.dropFirst()),
                    // Classify against the playlist's declared URL so a
                    // reordered `.ts` candidate never looks like video.
                    analysisURL: item.url
                )
            }
            let detector = RadioStationDetector(rules: rules)
            let snapshot = detector.buildSnapshot(channels: channels)
            cache.store(snapshot)
            return .success(snapshot)
        } catch let error as ProviderError {
            switch error {
            case .networkUnreachable, .timedOut, .serverError:
                if let cached = cache.load() {
                    return .offline(cached.snapshot)
                }
                return .failure(error.errorDescription ?? "Network problem.")
            default:
                return .failure(error.errorDescription ?? "Unexpected problem.")
            }
        } catch {
            return .failure("Something went wrong while loading the playlist.")
        }
    }

    // MARK: Cache

    func cachedSnapshot() -> LibrarySnapshot? {
        cache.load()?.snapshot
    }

    func clearCaches() {
        cache.clear()
    }

    /// Upgrades http:// direct sources to https:// when the portal is https.
    /// SECURITY: never logs the URLs; this is a best-effort privacy upgrade.
    private func upgradeToHTTPSIfPossible(_ url: URL, base: URL) -> URL {
        guard url.scheme?.lowercased() == "http", base.scheme?.lowercased() == "https" else {
            return url
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }

    /// Only http/https URLs can be played by AVPlayer.
    private func isPlayable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
