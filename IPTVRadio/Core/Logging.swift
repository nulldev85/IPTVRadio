import Foundation
import os

/// Central logging facility.
///
/// SECURITY: Every message passes through `Redactor` before it reaches the log
/// so that usernames, passwords and any credential-bearing URLs are scrubbed.
/// Never log raw provider URLs, credentials or tokens.
enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "IPTVRadio"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let parser = Logger(subsystem: subsystem, category: "parser")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}

/// Redacts secret material from strings before logging.
struct Redactor {
    /// Terms that must never appear in logs.
    private let secrets: [String]

    init(secrets: [String]) {
        // Ignore trivial values so we do not mangle unrelated text.
        self.secrets = secrets.filter { $0.count >= 4 }
    }

    init(credentials: ProviderCredentials?) {
        switch credentials {
        case let .xtream(cred):
            self.init(secrets: [cred.username, cred.password])
        case let .m3u(cred):
            self.init(secrets: [cred.url.absoluteString])
        case .none:
            self.init(secrets: [])
        }
    }

    /// Replaces every occurrence of each secret with "***".
    func redact(_ input: String) -> String {
        var output = input
        for secret in secrets {
            output = output.replacingOccurrences(of: secret, with: "***")
        }
        // Defensive: scrub common credential query parameters.
        output = output.replacingOccurrences(
            of: "(?i)(username|password|token|auth)=([^&\\s]+)",
            with: "$1=***",
            options: .regularExpression
        )
        return output
    }
}
