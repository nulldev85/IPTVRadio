import Foundation

/// Errors surfaced by the provider data layer.
///
/// SECURITY: `errorDescription` messages are deliberately generic and never
/// embed the request URL, username, password or tokens.
enum ProviderError: Error, LocalizedError, Equatable {
    case invalidServerURL
    case notAuthenticated
    case unauthorized
    case sessionExpired
    case networkUnreachable
    case timedOut
    case serverError(status: Int)
    case malformedResponse(String)
    case emptyPlaylist
    case insecureEndpointWarning
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The server address is not valid. Check the portal URL and try again."
        case .notAuthenticated:
            return "Sign in with your provider credentials to load channels."
        case .unauthorized:
            return "Your provider rejected the sign-in. Verify your username and password, and that your subscription is active."
        case .sessionExpired:
            return "Your subscription session appears to have expired. Refresh to sign in again."
        case .networkUnreachable:
            return "No network connection. Check your internet access and try again."
        case .timedOut:
            return "The provider took too long to respond. Try again in a moment."
        case .serverError:
            return "The provider server reported an error. Try again later."
        case .malformedResponse:
            return "The provider returned data this app could not understand. The playlist may be malformed."
        case .emptyPlaylist:
            return "The playlist contained no channels."
        case .insecureEndpointWarning:
            return "This provider uses an unencrypted HTTP connection. Your credentials may be visible on the network."
        case .cancelled:
            return "The request was cancelled."
        }
    }

    /// Whether retrying could plausibly succeed without user input.
    var isRetryable: Bool {
        switch self {
        case .networkUnreachable, .timedOut, .serverError:
            return true
        default:
            return false
        }
    }
}
