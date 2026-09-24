import SwiftUI

/// In-app stream diagnostics. The app is installed from CI artifacts, so users
/// typically have no Xcode console — everything needed to judge audio quality
/// (format, fallback position, bitrates) is shown here instead.
struct StreamDiagnosticsView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var appEnvironment: AppEnvironment

    /// The channel key field, seeded from what is stored for this station.
    @State private var channelKeyDraft = ""
    /// Station the draft was seeded for, so switching station reseeds it.
    @State private var draftStationID: String?

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
                    LabeledContent("Song info from stream", value: diagnostics.songInfoFromStream ? "Received" : "Not provided")
                    LabeledContent("Song info source", value: songSourceValue(diagnostics))
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
                                .foregroundStyle(Color.appTextSecondary)
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
                .appFormSection()
                // Rendered whenever a station is playing, not only once a
                // source has answered: the channel key field below is needed
                // exactly when nothing is answering.
                if playback.state.station != nil {
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
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                            }
                        }
                        if let station = playback.state.station {
                            channelKeyEditor(for: station)
                        }
                    } header: {
                        Text("Song lookup")
                    } footer: {
                        Text("Where the current track is looked up when the stream carries no metadata, and what each source answered. A show name is not a track: it is shown, but album art is only searched for once both an artist and a title are known.\n\nA status such as “HTTP 404” means the channel could not be matched by name at that source; “no song in response” means it was matched and is not playing a track right now.")
                    }
                    .appFormSection()
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
                                            .foregroundStyle(Color.appTextSecondary)
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
                    .appFormSection()
                }

                Section {
                    Text("Updated \(diagnostics.updatedAt.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(Color.appTextTertiary)
                }
                .appFormSection()
            } else {
                Section("Active stream") {
                    Text("No active stream. Play a station to collect diagnostics.")
                        .foregroundStyle(Color.appTextSecondary)
                }
                .appFormSection()
            }

            Section {
                Text("This app plays your provider's stream exactly as delivered — no transcoding, EQ or volume processing.\n\n“Observed bitrate” is the recent download rate and is highest right after playback starts; it does not describe audio quality. HLS streams often do not report audio bitrate figures at all.\n\nIf audio quality sounds low, use “Retry preferred formats” above: the app then probes the audio-only formats again instead of resuming on the endpoint it remembered, and the format line shows which option is playing.\n\nIf this station came from an M3U playlist link and sounds worse than another player, sign in with your provider's Xtream portal details (server URL, username, password) instead — that plays the provider's original stream rather than a re-packaged copy.")
                    .font(.footnote)
                    .foregroundStyle(Color.appTextSecondary)
            } header: {
                Text("How to read this")
            }
            .appFormSection()
        }
        .appScrollBackground()
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

    /// Channel key control for the playing station.
    ///
    /// The escape hatch for the whole feature. Broadcaster channel keys are not
    /// published anywhere authoritative and the panel's label for a channel is
    /// not the key, so no table or naming rule can be complete. Rather than
    /// leave a station permanently unable to show a song, the keys being tried
    /// are shown and the right one can be typed in.
    @ViewBuilder
    private func channelKeyEditor(for station: RadioStation) -> some View {
        let resolved = ChannelKeyResolver(overrides: appEnvironment.songLookupKeys).keys(for: station)
        VStack(alignment: .leading, spacing: 8) {
            if !resolved.isEmpty {
                LabeledContent("Channel keys tried", value: resolved.joined(separator: ", "))
                    .font(.footnote)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Channel key for this station")
                    .font(.footnote.weight(.medium))
                HStack(spacing: 10) {
                    TextField("e.g. octane", text: $channelKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .accessibilityIdentifier("diagnostics.channelKeyField")
                        .appFieldBackground()
                    Button("Save") {
                        appEnvironment.songLookupKeys.setKey(channelKeyDraft, for: station.id)
                        // Replayed so the next poll uses the new key straight
                        // away; a lookup otherwise waits out its 30s interval.
                        playback.retry()
                    }
                    .accessibilityIdentifier("diagnostics.saveChannelKey")
                }
                Text("Set this when the keys above come back “HTTP 404” — that means the channel could not be matched by name. Leave it empty to go back to automatic matching.")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .task(id: station.id) {
            guard draftStationID != station.id else { return }
            draftStationID = station.id
            channelKeyDraft = appEnvironment.songLookupKeys.key(for: station.id) ?? ""
        }
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
        case .song: return .appTextPrimary
        case .programme: return .appTextSecondary
        case .nothing: return .appTextTertiary
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
        case .playing: return .appTextPrimary
        case .failed: return .appTextSecondary
        case .notTried, .skipped: return .appTextTertiary
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
                .foregroundStyle(Color.appTextSecondary)
            Text(bitrateLine)
                .font(.caption2)
                .foregroundStyle(Color.appTextTertiary)
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
