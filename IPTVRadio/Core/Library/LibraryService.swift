import Foundation

/// Outcome of a library refresh, used to drive distinct UI states.
enum LibraryRefreshResult: Equatable {
    case success(LibrarySnapshot)
    case successFromCache(LibrarySnapshot)
    case offline(LibrarySnapshot?)
    case expired
    case failure(String)
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

    func refresh(credentials: XtreamCredentials, http: HTTPClient, rules: RadioDetectionRules) async -> LibraryRefreshResult {
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

            // Prefer the provider's own direct_source URL when it supplies one
            // (it is usually the unmodified source feed). Otherwise construct
            // the /live/ endpoint using the container the provider declared
            // for this stream (container_extension), not a hardcoded format —
            // many Xtream panels transcode .m3u8 to a fixed, lower audio
            // bitrate while other containers (e.g. .ts) are passed through.
            var rawChannels: [RawChannel] = streams.map { stream in
                let url: URL
                var usesDirect = false
                if let direct = Lenient.url(stream.directSource), stream.directSource?.isEmpty == false {
                    url = upgradeToHTTPSIfPossible(direct, base: client.baseURL)
                    usesDirect = true
                } else {
                    let format = Self.sanitizedContainerExtension(stream.containerExtension) ?? "m3u8"
                    url = client.streamURL(streamID: stream.streamID, format: format)
                }
                let group = categoriesByID[stream.categoryID ?? ""]?.name ?? ""
                return RawChannel(
                    name: stream.name,
                    url: url,
                    group: group,
                    logoURL: Lenient.url(stream.streamIcon),
                    tvgID: stream.epgChannelID,
                    source: .xtream,
                    categoryID: stream.categoryID,
                    usesDirectSource: usesDirect
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

    func refresh(credentials: M3UPlaylistCredentials, http: HTTPClient, rules: RadioDetectionRules) async -> LibraryRefreshResult {
        do {
            let client = M3UClient(http: http)
            let text = try await client.fetchPlaylistText(url: credentials.url)
            let items = M3UParser.parse(text)
            guard !items.isEmpty else {
                return .failure(ProviderError.malformedResponse("Playlist was empty or malformed.").errorDescription ?? "Playlist malformed.")
            }
            let channels = items.map { item in
                RawChannel(
                    name: item.name,
                    url: item.url,
                    group: item.groupTitle,
                    logoURL: item.logoURL,
                    tvgID: item.tvgID,
                    source: .m3u,
                    // An M3U playlist has no separate transcoded endpoint: the
                    // listed URL is always the exact, unmodified source.
                    usesDirectSource: true
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

    /// Only a known-safe set of extensions is honored; anything else falls
    /// back to the default so a malformed provider value can't build a
    /// broken endpoint. Pure/stateless, so it stays `nonisolated` and
    /// callable synchronously (including from non-actor test code) despite
    /// LibraryService itself being `@MainActor`.
    nonisolated static func sanitizedContainerExtension(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed: Set<String> = ["m3u8", "ts", "mp3", "aac"]
        return allowed.contains(trimmed) ? trimmed : nil
    }
}
