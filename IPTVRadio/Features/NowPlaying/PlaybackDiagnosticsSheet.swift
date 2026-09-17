import SwiftUI

/// Temporary in-app diagnostics panel for investigating audio quality on a
/// physical device. Every value shown here is safe to screenshot or read
/// aloud: no username, password, token or complete stream URL ever appears.
struct PlaybackDiagnosticsSheet: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Endpoint type", endpointDescription, id: "endpointType")
                    row("Direct source used", directSourceDescription, id: "directSource")
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("\"Direct source\" means the provider's own stream URL was used unmodified. Otherwise the app built a /live/ request using the container the provider declared for this station.")
                }

                Section("Audio track") {
                    row("Codec", diagnostics?.codec ?? "Not yet available", id: "codec")
                    row("Sample rate", sampleRateDescription, id: "sampleRate")
                    row("Channels", channelDescription, id: "channels")
                }

                Section("Bitrate (from AVPlayer access log)") {
                    row("Indicated", bitrateDescription(diagnostics?.indicatedBitrate), id: "indicatedBitrate")
                    row("Observed", bitrateDescription(diagnostics?.observedBitrate), id: "observedBitrate")
                    row("Average audio", bitrateDescription(diagnostics?.averageAudioBitrate), id: "averageAudioBitrate")
                }

                Section("Output") {
                    row("Current route", playback.currentRouteDescription, id: "route")
                }

                if let capturedAt = diagnostics?.capturedAt {
                    Section {
                        Text("Last updated \(capturedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("No username, password, token or complete stream URL is ever shown here or written to the device log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Playback Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("diagnostics.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("diagnostics.sheet")
    }

    private var diagnostics: PlaybackDiagnostics.Snapshot? { playback.diagnostics }

    private var endpointDescription: String {
        guard let diagnostics else { return "Buffering…" }
        if diagnostics.usesDirectSource {
            return "Provider direct source"
        }
        return "Provider /live/ endpoint (.\(diagnostics.streamExtension))"
    }

    private var directSourceDescription: String {
        guard let diagnostics else { return "Unknown" }
        return diagnostics.usesDirectSource ? "Yes" : "No"
    }

    private var sampleRateDescription: String {
        guard let rate = diagnostics?.sampleRate, rate > 0 else { return "Not yet available" }
        return String(format: "%.1f kHz", rate / 1000)
    }

    private var channelDescription: String {
        guard let channels = diagnostics?.channelCount, channels > 0 else { return "Not yet available" }
        switch channels {
        case 1: return "1 (mono)"
        case 2: return "2 (stereo)"
        default: return "\(channels)"
        }
    }

    private func bitrateDescription(_ value: Double?) -> String {
        guard let value, value > 0 else { return "Not yet available" }
        return String(format: "%.0f kbps", value / 1000)
    }

    private func row(_ label: String, _ value: String, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("diagnostics.value.\(id)")
        }
    }
}
