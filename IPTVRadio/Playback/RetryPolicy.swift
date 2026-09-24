import Foundation

/// How many times to reconnect, and how long to wait between attempts.
///
/// Pure logic, so the backoff is unit tested rather than observed. The
/// budget counts *consecutive* failures: a stream that reaches the player
/// resets it, so a station that reconnects cleanly once an hour is never
/// given up on.
struct RetryPolicy: Equatable {
    let maxAttempts: Int
    /// Backoff bases in seconds: 1s, 2s, 4s...
    static func backoff(forAttempt attempt: Int) -> TimeInterval {
        pow(2, Double(max(0, attempt - 1)))
    }

    func nextAction(afterAttempts attempts: Int) -> RetryDecision {
        if attempts < maxAttempts {
            return .retryAfterDelay(Self.backoff(forAttempt: attempts + 1))
        }
        return .giveUp
    }
}

enum RetryDecision: Equatable {
    case retryAfterDelay(TimeInterval)
    case giveUp
}
