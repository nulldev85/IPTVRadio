import Foundation

/// Stores provider credentials exclusively in the configured secret store
/// (Keychain in production) as one JSON item so writes are atomic.
actor CredentialsStore: Sendable {
    private static let account = "provider-credentials"

    struct StoredCredentials: Codable {
        var xtream: XtreamCredentials?
        var m3uURL: URL?
    }

    private let secrets: any SecretStoring
    private var cached: StoredCredentials?

    init(secrets: any SecretStoring = KeychainStore()) {
        self.secrets = secrets
    }

    func load() -> StoredCredentials? {
        if let cached { return cached }
        guard let data = try? secrets.loadData(account: Self.account) else { return nil }
        let decoded = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        cached = decoded
        return decoded
    }

    func save(_ value: StoredCredentials) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw KeychainStore.KeychainError.encodingFailed
        }
        try secrets.saveData(data, account: Self.account)
        cached = value
    }

    func clear() throws {
        try secrets.deleteData(account: Self.account)
        cached = nil
    }

    var redactor: Redactor {
        Redactor(secrets: {
            var secrets: [String] = []
            if let xt = cached?.xtream {
                secrets.append(xt.username)
                secrets.append(xt.password)
            }
            if let url = cached?.m3uURL {
                secrets.append(url.absoluteString)
            }
            return secrets
        }())
    }
}
