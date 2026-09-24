import SwiftUI

/// Reusable presentation states: loading, empty, offline, expired, error.
///
/// All five share one layout — a centred stack of glyph, headline, explanation
/// and an optional action — so an empty screen never looks like a different app
/// from a failed one.
private struct StateContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
        .background(Color.appBackground)
    }
}

/// The glyph every state leads with. Tertiary by default: a state screen should
/// read as quiet, not alarming.
private struct StateGlyph: View {
    let systemImage: String
    var color: Color = .appTextTertiary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 38, weight: .light))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

private struct StateTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.appTextPrimary)
            .multilineTextAlignment(.center)
    }
}

private struct StateMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.appTextSecondary)
            .multilineTextAlignment(.center)
    }
}

struct LoadingStateView: View {
    var message = "Loading stations…"

    var body: some View {
        StateContainer {
            ProgressView()
                .controlSize(.large)
            StateMessage(text: message)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String = "dot.radiowaves.left.and.right"

    var body: some View {
        StateContainer {
            StateGlyph(systemImage: systemImage)
            StateTitle(text: title)
            if !message.isEmpty {
                StateMessage(text: message)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OfflineStateView: View {
    var onRetry: () -> Void

    var body: some View {
        StateContainer {
            StateGlyph(systemImage: "wifi.slash")
            StateTitle(text: "You're offline")
            StateMessage(text: "Cached stations are shown. Reconnect and pull to refresh for the latest lineup.")
            Button("Try Again", action: onRetry)
                .buttonStyle(AppQuietButtonStyle())
                .padding(.top, 6)
                .accessibilityIdentifier("state.retry")
        }
    }
}

struct ExpiredSessionStateView: View {
    var onRetry: () -> Void

    var body: some View {
        StateContainer {
            StateGlyph(systemImage: "clock.badge.exclamationmark", color: .appAlert)
            StateTitle(text: "Session expired")
            StateMessage(text: "Your subscription session appears to have expired. Refresh your credentials or contact your provider.")
            Button("Refresh", action: onRetry)
                .buttonStyle(AppProminentButtonStyle())
                .padding(.top, 6)
        }
    }
}

struct ErrorStateView: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        StateContainer {
            StateGlyph(systemImage: "exclamationmark.triangle", color: .appAlert)
            StateTitle(text: "Something went wrong")
            StateMessage(text: message)
            Button("Try Again", action: onRetry)
                .buttonStyle(AppProminentButtonStyle())
                .padding(.top, 6)
                .accessibilityIdentifier("state.retry")
        }
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
