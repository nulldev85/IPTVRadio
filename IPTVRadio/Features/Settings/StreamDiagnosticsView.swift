import SwiftUI

/// In-app stream diagnostics. The app is installed from CI artifacts, so users
/// typically have no Xcode console — everything needed to judge audio quality
/// (format, fallback position, bitrates) is shown here instead.
struct StreamDiagnosticsView: View {
    @EnvironmentObject private var playback: PlaybackEngine

    var body: some View {
        Form {
            if let diagnostics = playback.streamDiagnostics {
                Section("Active stream") {
                    LabeledContent("Station", value: diagnostics.stationName)
                    LabeledContent(
                        "Format",
                        value: "\(formatName(diagnostics.streamType)), option \(diagnostics.formatIndex) of \(diagnostics.formatCount)"
                    )
                    LabeledContent("Indicated bitrate", value: bitrate(diagnostics.indicatedBitrate))
                    LabeledContent("Observed bitrate (download rate)", value: bitrate(diagnostics.observedBitrate))
                    LabeledContent("Average audio bitrate", value: bitrate(diagnostics.averageAudioBitrate))
                    LabeledContent("Audio track data rate", value: bitrate(diagnostics.audioTrackDataRate))
                    if let audioFormat = diagnostics.audioFormat {
                        LabeledContent("Audio format", value: audioFormat)
                    }
                    LabeledContent("Playback engine", value: diagnostics.playbackEngine.label)
                    LabeledContent("Song info from stream", value: diagnostics.songInfoFromStream ? "Received" : "Not provided")
                    LabeledContent(
                        "Song info source",
                        value: diagnostics.songInfoFromStream
                            ? "The stream itself"
                            : (diagnostics.songInfoSource ?? "None answered")
                    )
                    if songMetadataIsUnreadable(diagnostics) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This engine cannot read song titles from HLS")
                                .font(.footnote.weight(.medium))
                            Text("HLS carries the current song as ID3 timed metadata inside the stream. The compatibility engine only reads ICY song titles, which HLS does not use, so no track can appear however good the stream is. Switch Playback engine to \"Standard (AVPlayer)\" in Settings ▸ Playback and relaunch the app to read them.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("diagnostics.engineCannotReadSongInfo")
                    }
                    LabeledContent("Audio-only rendition", value: audioOnlyValue(diagnostics))
                    if let variants = diagnostics.availableVariants, variants > 0 {
                        LabeledContent("Variants in stream", value: "\(variants)")
                    }
                    if let failure = diagnostics.lastFormatFailure {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Skipped a format")
                                .font(.footnote.weight(.medium))
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("diagnostics.previousFailure")
                    }
                    if let bandwidth = diagnostics.declaredAudioBandwidth {
                        LabeledContent("Declared audio bandwidth", value: bitrate(bandwidth))
                    }
                    if let requests = diagnostics.mediaRequests {
                        LabeledContent("Media requests", value: "\(requests)")
                    }
                }
                if !diagnostics.candidates.isEmpty {
                    Section {
                        ForEach(diagnostics.candidates) { candidate in
                            LabeledContent {
                                Text(outcomeText(candidate.outcome))
                                    .foregroundStyle(outcomeColor(candidate.outcome))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(candidate.index). \(formatName(candidate.format))")
                                    if case .failed(let reason) = candidate.outcome, let reason {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button("Retry preferred formats") {
                            playback.retryPreferredFormats()
                        }
                        .accessibilityIdentifier("diagnostics.retryPreferredFormats")
                        Button("Forget format and stop") {
                            playback.forgetRememberedFormat()
                        }
                        .accessibilityIdentifier("diagnostics.forgetRememberedFormat")
                    } header: {
                        Text("Stream formats tried")
                    } footer: {
                        Text("Retrying replays the station straight away, so a connection is open again while the preferred formats are probed — and a panel that caps connections refuses a second one with the same 403 it uses for a format it will not serve. To tell those apart, use “Forget format and stop”, wait a minute for the provider to release the connection, then play the station again: the probe then runs with nothing else open.\n\n"
                             + (diagnostics.startedAtRememberedEndpoint
                             ? "This station starts on a remembered endpoint, so the formats above it are skipped rather than retried. That keeps starts fast, but the audio-only formats (MP3/AAC) are the ones that carry per-song titles — retry to probe them again."
                             : "Formats are tried in order. The audio-only ones (MP3/AAC) are preferred: they carry the original audio and are the only formats that publish per-song titles."))
                    }
                }

                Section {
                    Text("Updated \(diagnostics.updatedAt.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Active stream") {
                    Text("No active stream. Play a station to collect diagnostics.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("This app plays your provider's stream exactly as delivered — no transcoding, EQ or volume processing.\n\n“Observed bitrate” is the recent download rate and is highest right after playback starts; it does not describe audio quality. HLS streams often do not report audio bitrate figures at all.\n\nIf audio quality sounds low, switch “Stream format” in Settings ▸ Playback and compare — the format line above shows which option is playing.\n\nIf this station came from an M3U playlist link and sounds worse than another player, sign in with your provider's Xtream portal details (server URL, username, password) instead — that plays the provider's original stream rather than a re-packaged copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How to read this")
            }
        }
        .navigationTitle("Stream diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func audioOnlyValue(_ diagnostics: StreamDiagnostics) -> String {
        if diagnostics.usingAudioOnlyRendition { return "Playing the dedicated audio track" }
        if diagnostics.manifestChecked { return "Not offered by this stream" }
        return "Not checked"
    }

    private func formatName(_ streamExtension: String) -> String {
        switch streamExtension.lowercased() {
        case "ts": return "MPEG-TS (original)"
        case "m3u8": return "HLS (.m3u8)"
        case "": return "unknown"
        default: return streamExtension.uppercased()
        }
    }

    /// True when the engine in use structurally cannot surface this stream's
    /// song metadata, as opposed to the stream simply not carrying any.
    private func songMetadataIsUnreadable(_ diagnostics: StreamDiagnostics) -> Bool {
        diagnostics.playbackEngine == .vlc
            && diagnostics.streamType.lowercased() == "m3u8"
            && !diagnostics.songInfoFromStream
    }

    private func outcomeText(_ outcome: StreamCandidateReport.Outcome) -> String {
        switch outcome {
        case .playing: return "Playing"
        case .failed: return "Failed"
        case .notTried: return "Not tried"
        case .skipped: return "Skipped"
        }
    }

    private func outcomeColor(_ outcome: StreamCandidateReport.Outcome) -> Color {
        switch outcome {
        case .playing: return .green
        case .failed: return .orange
        case .notTried, .skipped: return .secondary
        }
    }

    private func bitrate(_ value: Double?) -> String {
        guard let value, value > 0 else { return "not reported" }
        return String(format: "%.0f kbps", value / 1000)
    }
}

/// Compact live diagnostics line shown on the now playing screen.
struct StreamDiagnosticsSummaryCard: View {
    let diagnostics: StreamDiagnostics

    var body: some View {
        VStack(spacing: 3) {
            Text(formatLine)
                .font(.caption2.weight(.medium))
            Text(bitrateLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nowplaying.diagnostics")
    }

    private var formatLine: String {
        let name: String
        switch diagnostics.streamType.lowercased() {
        case "ts": name = "MPEG-TS"
        case "m3u8": name = "HLS"
        case "": name = "stream"
        default: name = diagnostics.streamType.uppercased()
        }
        return "\(name) · option \(diagnostics.formatIndex) of \(diagnostics.formatCount)"
    }

    private var bitrateLine: String {
        guard let bitrate = diagnostics.primaryBitrate else {
            return "Bitrate not reported by the stream"
        }
        return String(format: "%.0f kbps", bitrate / 1000)
    }
}
