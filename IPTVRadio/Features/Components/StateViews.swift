import SwiftUI

/// Reusable presentation states: loading, empty, offline, expired, error.
struct LoadingStateView: View {
    var message = "Loading stations…"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String = "dot.radiowaves.left.and.right"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(AetherTheme.mutedIcon)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

struct OfflineStateView: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(AetherTheme.mutedIcon)
                .accessibilityHidden(true)
            Text("You're offline")
                .font(.headline)
            Text("Cached stations are shown. Reconnect and pull to refresh for the latest lineup.")
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("state.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

struct ExpiredSessionStateView: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Session expired")
                .font(.headline)
            Text("Your subscription session appears to have expired. Refresh your credentials or contact your provider.")
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Refresh", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

struct ErrorStateView: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AetherTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("state.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

/// Wrapper showing the right state view for a LibraryViewModel state.
struct LibraryStateView: View {
    let state: LibraryViewModel.State
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView()
        case .empty:
            EmptyStateView(
                title: "No radio stations found",
                message: "Your provider's lineup didn't include any audio channels. Try adjusting the detection rules in Settings."
            )
        case .offline:
            OfflineStateView(onRetry: onRetry)
        case .expired:
            ExpiredSessionStateView(onRetry: onRetry)
        case .malformed(let message), .error(let message):
            ErrorStateView(message: message, onRetry: onRetry)
        case .loaded:
            EmptyStateView(title: "Ready", message: "")
        }
    }
}
