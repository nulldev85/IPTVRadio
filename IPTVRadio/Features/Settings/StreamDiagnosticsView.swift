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
                    LabeledContent("Song info source", value: songSourceValue(diagnostics))
                    if songMetadataIsUnreadable(diagnostics) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This engine cannot read song titles from HLS")
                                .font(.footnote.weight(.medium))
                            Text("HLS carries the current song as ID3 timed metadata inside the stream. The compatibility engine only reads ICY song titles, which HLS does not use, so no track from the stream can appear however good it is.\n\nSwitching Playback engine to \"Standard (AVPlayer)\" in Settings ▸ Playback reads ID3 — but only if the stream actually carries it, and on many panels it carries none. That engine also cannot play raw MPEG-TS, so it falls back to the re-packaged HLS copy, which sounds worse. Try it once: if “Song info from stream” still reads “Not provided”, the stream has no metadata and the compatibility engine is the better choice.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("diagnostics.engineCannotReadSongInfo")
                    }
                    if streamCarriesNoMetadata(diagnostics) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This stream carries no song metadata")
                                .font(.footnote.weight(.medium))
                            Text("The standard engine does read ID3 timed metadata, and this stream is supplying none — so the missing track is the stream, not the engine. Nothing is gained here over the compatibility engine, and something is lost: the standard engine cannot play raw MPEG-TS, so it is playing the re-packaged HLS copy instead of your provider's original audio. Switch Playback engine back to \"Compatibility (VLC)\" for the better-sounding stream; the song is looked up from the broadcaster either way.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("diagnostics.streamCarriesNoMetadata")
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
                if !diagnostics.songSources.isEmpty {
                    Section {
                        ForEach(diagnostics.songSources) { report in
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent {
                                    Text(songOutcomeText(report.outcome))
                                        .foregroundStyle(songOutcomeColor(report.outcome))
                                } label: {
                                    Text(report.source)
                                }
                                if let detail = report.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Song lookup")
                    } footer: {
                        Text("Where the current track is looked up when the stream carries no metadata, and what each source answered. A show name is not a track: it is shown, but album art is only searched for once both an artist and a title are known.\n\nA status such as “HTTP 404” means the channel could not be matched by name at that source; “no song in response” means it was matched and is not playing a track right now.")
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
                                    if engineCannotPlay(candidate, diagnostics: diagnostics) {
                                        Text("The standard engine cannot play raw MPEG-TS — an engine limit, not a fault in your provider's stream.")
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

    /// True when the engine that *can* read in-stream song metadata is running
    /// and the stream is still supplying none.
    ///
    /// This is the measured answer to the hint above, and it points the other
    /// way: nothing is gained by staying on the standard engine, and the
    /// original MPEG-TS audio is lost while doing so.
    private func streamCarriesNoMetadata(_ diagnostics: StreamDiagnostics) -> Bool {
        diagnostics.playbackEngine == .avplayer
            && !diagnostics.songInfoFromStream
            && diagnostics.streamType.lowercased() == "m3u8"
    }

    /// True when this candidate failed because the running engine cannot play
    /// that container at all, rather than because the provider refused it.
    private func engineCannotPlay(
        _ candidate: StreamCandidateReport,
        diagnostics: StreamDiagnostics
    ) -> Bool {
        guard diagnostics.playbackEngine == .avplayer else { return false }
        guard case .failed = candidate.outcome else { return false }
        return candidate.format == "ts"
    }

    /// The song-info source line. Names the source and, when what it supplied
    /// is a show name rather than a track, says so — naming the source alone
    /// reads as "the song came from here".
    private func songSourceValue(_ diagnostics: StreamDiagnostics) -> String {
        if diagnostics.songInfoFromStream { return "The stream itself" }
        guard let source = diagnostics.songInfoSource else { return "None answered" }
        return diagnostics.songInfoIsProgrammeOnly ? "\(source) (show info only)" : source
    }

    private func songOutcomeText(_ outcome: SongSourceReport.Outcome) -> String {
        switch outcome {
        case .song: return "Track"
        case .programme: return "Show info"
        case .nothing: return "Nothing"
        }
    }

    private func songOutcomeColor(_ outcome: SongSourceReport.Outcome) -> Color {
        switch outcome {
        case .song: return .green
        case .programme: return .orange
        case .nothing: return .secondary
        }
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
