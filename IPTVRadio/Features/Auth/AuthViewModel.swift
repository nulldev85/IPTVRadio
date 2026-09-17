import Foundation
import SwiftUI

/// Handles sign-in, session restore and sign-out.
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .unknown
    @Published var insecureEndpointWarning: String?

    private let credentials: CredentialsStore
    private let settings: SettingsStore

    init(credentials: CredentialsStore, settings: SettingsStore) {
        self.credentials = credentials
        self.settings = settings
    }

    /// Restores any previously stored credentials at launch.
    func restoreSession() {
        Task {
            if let stored = await credentials.load() {
                if let xtream = stored.xtream {
                    warnIfInsecure(xtream)
                }
                authState = .active(SessionInfo(
                    isAuthenticated: true,
                    status: nil,
                    expiryDate: nil,
                    maxConnections: nil,
                    activeConnections: nil,
                    serverURL: nil,
                    usesInsecureHTTP: stored.xtream?.usesInsecureHTTP ?? false
                ))
            } else {
                authState = .loggedOut
            }
        }
    }

    /// Signs in with Xtream credentials, validating them against the provider.
    func signIn(xtream: XtreamCredentials, httpClient: HTTPClient) async -> Result<SessionInfo, ProviderError> {
        guard xtream.normalizedBaseURL != nil else {
            return .failure(.invalidServerURL)
        }
        do {
            let client = try XtreamClient(credentials: xtream, http: httpClient)
            let session = try await client.authenticate()
            if session.isExpired {
                authState = .expired
                return .failure(.sessionExpired)
            }
            do {
                try await credentials.save(CredentialsStore.StoredCredentials(xtream: xtream, m3uURL: nil))
            } catch {
                AppLogger.persistence.error("Keychain save failed")
                return .failure(.malformedResponse("Could not store credentials securely."))
            }
            settings.authMode = .xtream
            warnIfInsecure(xtream)
            authState = .active(session)
            return .success(session)
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.networkUnreachable)
        }
    }

    /// Saves M3U playlist credentials (no server round-trip needed).
    func signIn(m3u url: URL) async -> Result<SessionInfo, ProviderError> {
        do {
            try await credentials.save(CredentialsStore.StoredCredentials(xtream: nil, m3uURL: url))
        } catch {
            return .failure(.malformedResponse("Could not store credentials securely."))
        }
        settings.authMode = .m3u
        insecureEndpointWarning = url.scheme?.lowercased() == "http"
            ? "This playlist URL uses unencrypted HTTP. Anyone on your network may be able to read it."
            : nil
        authState = .active(SessionInfo(
            isAuthenticated: true, status: nil, expiryDate: nil,
            maxConnections: nil, activeConnections: nil,
            serverURL: url, usesInsecureHTTP: url.scheme?.lowercased() == "http"
        ))
        return .success(SessionInfo(
            isAuthenticated: true, status: nil, expiryDate: nil,
            maxConnections: nil, activeConnections: nil,
            serverURL: url, usesInsecureHTTP: false
        ))
    }

    /// Signs out and clears all locally stored secrets and cached data.
    func signOut() {
        Task {
            try? await credentials.clear()
            authState = .loggedOut
            insecureEndpointWarning = nil
        }
    }

    private func warnIfInsecure(_ cred: XtreamCredentials) {
        if cred.usesInsecureHTTP {
            insecureEndpointWarning = "Your provider portal uses an unencrypted HTTP connection. Sign-in details could be visible to others on your network. Ask your provider for an HTTPS address."
        } else {
            insecureEndpointWarning = nil
        }
    }
}
