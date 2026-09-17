import Foundation
import SwiftUI

/// Drives the station library: refresh, search, filtering, and distinct
/// presentation states (loading, empty, offline, expired, malformed).
@MainActor
final class LibraryViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case offline
        case expired
        case malformed(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: LibrarySnapshot?
    @Published private(set) var isRefreshing = false
    @Published var searchQuery = ""

    private let libraryService: LibraryService
    private let settings: SettingsStore
    private let credentials: CredentialsStore
    private let httpClient: HTTPClient

    init(
        libraryService: LibraryService,
        settings: SettingsStore,
        credentials: CredentialsStore,
        httpClient: HTTPClient
    ) {
        self.libraryService = libraryService
        self.settings = settings
        self.credentials = credentials
        self.httpClient = httpClient
    }

    // MARK: Derived data

    var siriusStations: [RadioStation] {
        snapshot?.siriusStations ?? []
    }

    var radioStations: [RadioStation] {
        let all = snapshot?.allRadioStations ?? []
        if settings.siriusOnly { return all.filter { isSirius($0) } }
        return all
    }

    var categories: [ChannelCategory] {
        var cats = snapshot?.categories ?? []
        if settings.siriusOnly {
            cats = cats.filter {
                let n = $0.name.lowercased()
                return n.contains("sirius") || n.contains("sxm")
            }
        }
        return cats
    }

    private func isSirius(_ station: RadioStation) -> Bool {
        SiriusMatcher.score(
            name: station.name,
            group: station.groupTitle,
            tvgID: station.tvgID,
            keywords: settings.detectionRules.siriusKeywords
        ) > 0
    }

    /// Search across station names, groups (genres/categories) and tvg ids.
    func searchResults() -> [RadioStation] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        return radioStations.filter { station in
            station.name.lowercased().contains(query)
                || station.groupTitle.lowercased().contains(query)
                || (station.tvgID ?? "").lowercased().contains(query)
        }
    }

    // MARK: Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let stored = await credentials.load() else {
            state = .error(ProviderError.notAuthenticated.errorDescription ?? "Sign in required.")
            return
        }

        let rules = settings.detectionRules
        let result: LibraryRefreshResult
        if let xtream = stored.xtream {
            result = await libraryService.refresh(credentials: xtream, http: httpClient, rules: rules)
        } else if let m3uURL = stored.m3uURL {
            result = await libraryService.refresh(
                credentials: M3UPlaylistCredentials(url: m3uURL),
                http: httpClient,
                rules: rules
            )
        } else {
            state = .error(ProviderError.notAuthenticated.errorDescription ?? "Sign in required.")
            return
        }
        apply(result)
    }

    private func apply(_ result: LibraryRefreshResult) {
        switch result {
        case .success(let snapshot):
            self.snapshot = snapshot
            state = snapshot.allRadioStations.isEmpty ? .empty : .loaded
        case .successFromCache(let snapshot):
            self.snapshot = snapshot
            state = .loaded
        case .offline(let snapshot):
            self.snapshot = snapshot
            state = .offline
        case .expired:
            state = .expired
        case .failure(let message):
            self.snapshot = libraryService.cachedSnapshot()
            if message.lowercased().contains("malformed") || message.lowercased().contains("could not understand") {
                state = .malformed(message)
            } else if self.snapshot == nil {
                state = .error(message)
            } else {
                state = .offline
            }
        }
    }

    /// Shows cached stations instantly at launch while a refresh happens.
    func restoreFromCache() {
        if let cached = libraryService.cachedSnapshot(), !cached.allRadioStations.isEmpty {
            snapshot = cached
            state = .loaded
        }
    }

    func clearCacheData() {
        libraryService.clearCaches()
        snapshot = nil
        state = .idle
    }

    // MARK: UI-test support

    func injectForUITest(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        state = snapshot.allRadioStations.isEmpty ? .empty : .loaded
    }
}
