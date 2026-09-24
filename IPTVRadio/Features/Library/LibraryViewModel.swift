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
    /// In-flight refresh, kept outside SwiftUI's task lifetime so the load
    /// always completes even if the view task that started it is cancelled.
    private var refreshTask: Task<Void, Never>?
    /// Hard cap on a single provider fetch (guarantees the UI leaves loading).
    private let refreshTimeout: TimeInterval

    init(
        libraryService: LibraryService,
        settings: SettingsStore,
        credentials: CredentialsStore,
        httpClient: HTTPClient,
        refreshTimeout: TimeInterval = 75
    ) {
        self.libraryService = libraryService
        self.settings = settings
        self.credentials = credentials
        self.httpClient = httpClient
        self.refreshTimeout = refreshTimeout
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

    /// Refreshes the library. The work runs in an unstructured task owned by
    /// this view model, so it always runs to completion and always leaves the
    /// UI in a terminal state (loaded / offline / error) — even if the view
    /// task that triggered it is cancelled. Concurrent calls join the
    /// in-flight refresh instead of being dropped.
    func refresh() async {
        if let existing = refreshTask {
            await existing.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        if snapshot == nil {
            state = .loading
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let stored = await credentials.load() else {
            state = .error(ProviderError.notAuthenticated.errorDescription ?? "Sign in required.")
            return
        }

        var result = await fetch(stored: stored)

        // One automatic retry for transient provider/network problems when we
        // have nothing cached to show.
        if case .failure = result, snapshot == nil {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            result = await fetch(stored: stored)
        }
        apply(result)
    }

    /// Runs the provider fetch with a hard timeout so the UI can never stay
    /// stuck on "Loading" because of a hung request.
    private func fetch(stored: CredentialsStore.StoredCredentials) async -> LibraryRefreshResult {
        let rules = settings.detectionRules
        let timeoutMessage = "Your provider took too long to respond. Check your connection, then pull to refresh."
        return await withTimeout(
            seconds: refreshTimeout,
            timeoutValue: .failure(timeoutMessage)
        ) { [libraryService, httpClient] in
            if let xtream = stored.xtream {
                return await libraryService.refresh(
                    credentials: xtream,
                    http: httpClient,
                    rules: rules
                )
            }
            if let m3uURL = stored.m3uURL {
                return await libraryService.refresh(
                    credentials: M3UPlaylistCredentials(url: m3uURL),
                    http: httpClient,
                    rules: rules
                )
            }
            return .failure(ProviderError.notAuthenticated.errorDescription ?? "Sign in required.")
        }
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

    // MARK: Fresh station resolution

    private var stationIndex: [String: RadioStation]?
    private var stationIndexGeneratedAt: Date?

    /// Resolves a station copy saved by an older app version (favorites,
    /// history) to the current library's version, so playback always uses
    /// fresh stream URLs and format candidates. Falls back to the given
    /// station when no fresh match exists (e.g. offline).
    func freshStation(matching station: RadioStation) -> RadioStation {
        guard let snapshot else { return station }
        if stationIndex == nil || stationIndexGeneratedAt != snapshot.generatedAt {
            var index: [String: RadioStation] = [:]
            for candidate in snapshot.allRadioStations {
                index[Self.stationIndexKey(name: candidate.name, source: candidate.source)] = candidate
            }
            stationIndex = index
            stationIndexGeneratedAt = snapshot.generatedAt
        }
        return stationIndex?[Self.stationIndexKey(name: station.name, source: station.source)] ?? station
    }

    private static func stationIndexKey(name: String, source: RadioStation.Source) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "|" + source.rawValue
    }

    func clearCacheData() {
        libraryService.clearCaches()
        snapshot = nil
        stationIndex = nil
        stationIndexGeneratedAt = nil
        state = .idle
    }

    // MARK: UI-test support

    func injectForUITest(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        state = snapshot.allRadioStations.isEmpty ? .empty : .loaded
    }
}

/// Runs `operation` and returns `timeoutValue` if it does not finish within
/// `seconds`. Guarantees callers can never wait forever on a hung request.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    timeoutValue: T,
    _ operation: @escaping @Sendable () async -> T
) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return timeoutValue
        }
        let result = await group.next() ?? timeoutValue
        group.cancelAll()
        return result
    }
}
