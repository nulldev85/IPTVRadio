import Foundation

/// Mock HTTP client used in UI-test mode so no network is touched.
/// Answers the three Xtream endpoints with embedded fixture data.
struct MockHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url?.absoluteString ?? ""
        let body: String
        if url.contains("get_live_categories") {
            body = #"[
                {"category_id": "1", "category_name": "SiriusXM", "parent_id": 0},
                {"category_id": "2", "category_name": "Music Radio", "parent_id": 0},
                {"category_id": "3", "category_name": "Talk Radio", "parent_id": 0}
            ]"#
        } else if url.contains("get_live_streams") {
            body = #"[
                {"num": 1, "name": "SiriusXM Hits 1", "stream_type": "live", "stream_id": "8020", "category_id": "1"},
                {"num": 2, "name": "SiriusXM Octane", "stream_type": "live", "stream_id": "8021", "category_id": "1"},
                {"num": 3, "name": "Jazz Cafe Radio", "stream_type": "live", "stream_id": "9002", "category_id": "2"}
            ]"#
        } else {
            body = #"{"user_info": {"auth": 1, "status": "Active", "exp_date": "4102444800"}, "server_info": {"url": "demo.example.net", "port": "80", "https_port": "443"}}"#
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.local")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}

/// Mock audio player that simulates connect-then-play for UI tests.
@MainActor
final class MockAudioPlayer: AudioPlayerControlling {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onEnded: (() -> Void)?

    func load(url: URL) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.onReady?()
        }
    }

    func play() {}
    func pause() {}
    func stop() {}
}

/// Scenarios selectable from UI tests via launch arguments.
enum UITestScenario: String {
    case login = "UITestLogin"
    case browse = "UITestBrowse"
    case search = "UITestSearch"
    case favorites = "UITestFavorites"
    case nowPlaying = "UITestNowPlaying"
}

enum UITestSupport {
    /// Sample library built from embedded fixture data. Contains no real
    /// provider data and no credentials.
    static let sampleChannels: [RawChannel] = {
        func ch(_ name: String, _ group: String, host: String = "stream.example.net", path: String) -> RawChannel {
            RawChannel(
                name: name,
                url: URL(string: "https://\(host)\(path)")!,
                group: group,
                logoURL: nil,
                tvgID: nil,
                source: .xtream
            )
        }
        return [
            ch("SiriusXM Hits 1", "SiriusXM", path: "/live/8020.m3u8"),
            ch("SiriusXM Octane", "SiriusXM", path: "/live/8021.m3u8"),
            ch("SiriusXM PopRocks", "SiriusXM", path: "/live/8022.m3u8"),
            ch("SXM Faction Talk", "SiriusXM", path: "/live/8023.m3u8"),
            ch("Classic Vinyl FM", "Music Radio", path: "/live/9001.mp3"),
            ch("Jazz Cafe Radio", "Music Radio", path: "/live/9002.mp3"),
            ch("Country Roads FM", "Country", path: "/live/9003.aac"),
            ch("News Talk 101", "Talk Radio", path: "/live/9004.mp3"),
            ch("Edge Rock Radio", "Rock", path: "/live/9005.aacp"),
            ch("Late Night Talk Radio", "Talk Radio", path: "/live/9006.mp3"),
        ]
    }()

    static func scenario(from arguments: [String]) -> UITestScenario? {
        for argument in arguments {
            if argument.hasPrefix("-UITestScenario=") {
                let raw = argument.replacingOccurrences(of: "-UITestScenario=", with: "")
                return UITestScenario(rawValue: raw)
            }
        }
        return nil
    }

    @MainActor
    static func configure(environment: AppEnvironment, scenario: UITestScenario) {
        // Deterministic settings for stable UI assertions.
        environment.settings.cellularAllowed = true
        environment.settings.showAllStations = true

        switch scenario {
        case .login:
            environment.auth.authState = .loggedOut
        case .browse:
            environment.library.injectForUITest(snapshot: makeSnapshot())
            environment.auth.authState = .active(uitestSession())
        case .search:
            environment.library.injectForUITest(snapshot: makeSnapshot())
            environment.auth.authState = .active(uitestSession())
        case .favorites:
            environment.library.injectForUITest(snapshot: makeSnapshot())
            environment.auth.authState = .active(uitestSession())
            for station in makeSnapshot().siriusStations.prefix(2) {
                environment.favorites.add(station)
            }
        case .nowPlaying:
            environment.library.injectForUITest(snapshot: makeSnapshot())
            environment.auth.authState = .active(uitestSession())
            let station = makeSnapshot().siriusStations[0]
            environment.playback.play(station, in: [station])
        }
    }

    static func makeSnapshot() -> LibrarySnapshot {
        RadioStationDetector(rules: .default).buildSnapshot(channels: sampleChannels)
    }

    static func uitestSession() -> SessionInfo {
        SessionInfo(
            isAuthenticated: true,
            status: "Active",
            expiryDate: nil,
            maxConnections: 2,
            activeConnections: 0,
            serverURL: URL(string: "https://demo.example.net"),
            usesInsecureHTTP: false
        )
    }
}
