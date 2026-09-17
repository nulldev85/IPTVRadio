import Foundation

/// Credentials the user supplies. Stored only in the Keychain.
enum ProviderCredentials: Hashable, Codable {
    case xtream(XtreamCredentials)
    case m3u(M3UPlaylistCredentials)

    var redactor: Redactor {
        switch self {
        case let .xtream(cred):
            return Redactor(secrets: [cred.username, cred.password])
        case let .m3u(cred):
            return Redactor(secrets: cred.url.absoluteString)
        }
    }
}

/// Xtream Codes API style credentials.
struct XtreamCredentials: Hashable, Codable {
    var serverInput: String
    var username: String
    var password: String

    /// True when the (possibly normalized) base URL uses plain HTTP.
    var usesInsecureHTTP: Bool {
        normalizedBaseURL?.scheme?.lowercased() == "http"
    }

    /// Normalizes user input such as "host:8080", "http://host:port" or a full
    /// player_api.php URL down to a base URL. Returns nil when unparseable.
    var normalizedBaseURL: URL? {
        Self.normalizeServerInput(serverInput)
    }

    static func normalizeServerInput(_ input: String) -> URL? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip a full player_api.php path down to the host root.
        if let range = trimmed.range(of: "player_api.php", options: .caseInsensitive) {
            trimmed = String(trimmed[..<range.lowerBound])
        }
        // Also tolerate a trailing "/c/" or "/" style portal paths.
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }

        // If the user did not type a scheme, assume HTTPS first (secure by default).
        if !trimmed.lowercased().contains("://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// All URLs that could contain credentials in query or path.
    var sensitiveStrings: [String] {
        [username, password]
    }
}

/// Simple M3U playlist URL import.
struct M3UPlaylistCredentials: Hashable, Codable {
    var url: URL
}

/// Session information returned by the Xtream `player_api.php` auth call.
struct SessionInfo: Codable, Hashable, Sendable {
    var isAuthenticated: Bool
    var status: String?
    var expiryDate: Date?
    var maxConnections: Int?
    var activeConnections: Int?
    var serverURL: URL?
    var usesInsecureHTTP: Bool

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return Date() >= expiry
    }
}
