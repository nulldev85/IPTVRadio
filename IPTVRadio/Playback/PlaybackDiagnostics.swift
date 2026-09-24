import Foundation
import AVFoundation
import CoreMedia

/// Describes the decoded audio track (codec, sample rate, channel layout).
/// Low-grade source audio (e.g. HE-AAC at 24 kHz) is visible here, which
/// distinguishes a weak provider source from an app-side problem.
enum AudioFormatDescriber {
    static func describe(codec: UInt32, sampleRate: Double, channels: UInt32) -> String {
        var parts: [String] = [codecName(codec)]
        if sampleRate > 0 {
            parts.append(String(format: "%.1f kHz", sampleRate / 1000))
        }
        if channels > 0 {
            switch channels {
            case 1: parts.append("mono")
            case 2: parts.append("stereo")
            default: parts.append("\(channels) ch")
            }
        }
        return parts.joined(separator: " · ")
    }

    static func codecName(_ fourCC: UInt32) -> String {
        switch fourCCString(fourCC) {
        case "aac ": return "AAC-LC"
        case "aacp": return "HE-AAC"
        case "ac-3": return "AC-3"
        case "ec-3": return "E-AC-3"
        case "alac": return "ALAC"
        case "mp3 ": return "MP3"
        case "opus": return "Opus"
        case "lpcm": return "PCM"
        default:
            let raw = fourCCString(fourCC).trimmingCharacters(in: .whitespaces)
            return raw.isEmpty ? "unknown" : raw.uppercased()
        }
    }

    static func fourCCString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}

/// A snapshot of stream quality information collected from AVPlayer's access
/// log and the audio track. Contains no URLs or credentials.
struct StreamDiagnosticsSample: Equatable {
    var streamExtension: String
    var indicatedBitrate: Double?
    var observedBitrate: Double?
    var averageAudioBitrate: Double?
    var audioTrackDataRate: Double?
    var mediaRequests: Int?
    /// Decoded audio codec/sample rate/channels, e.g. "AAC-LC · 44.1 kHz · stereo".
    var audioFormat: String? = nil
}

/// What became of one stream-format candidate for the current station.
///
/// SECURITY: carries the container format only, never the URL — provider
/// stream URLs embed the username and password.
struct StreamCandidateReport: Equatable, Identifiable {
    enum Outcome: Equatable {
        /// This candidate is the one currently playing.
        case playing
        /// Tried and rejected. Carries the sanitized reason when there is one.
        case failed(String?)
        /// Never reached, because an earlier candidate worked.
        case notTried
        /// Jumped over because a remembered endpoint won on a previous play.
        case skipped
    }

    /// 1-based, matching the "option N of M" line.
    var index: Int
    /// Lowercased container extension, e.g. "ts", "mp3".
    var format: String
    var outcome: Outcome

    var id: Int { index }
}

/// What one out-of-stream song source did on the last lookup.
///
/// Shown per source rather than collapsed into one line, because the useful
/// question is never "is a song showing" but "which source failed, and how":
/// an EPG listing a show, a metadata host answering 403 and a device with no
/// network all look the same on the now-playing bar.
struct SongSourceReport: Equatable, Identifiable {
    /// The source's label, e.g. "provider EPG".
    var source: String
    /// What it produced: a song, programme info, or nothing.
    var outcome: Outcome
    /// The source's own note, already free of URLs and credentials.
    var detail: String?

    enum Outcome: Equatable {
        /// A title *and* an artist: an actual track.
        case song
        /// A title with no artist — a show name, not a track.
        case programme
        /// Nothing usable came back.
        case nothing
    }

    var id: String { source }
}

/// User-visible diagnostics for the currently playing stream.
struct StreamDiagnostics: Equatable {
    var stationName: String
    var formatIndex: Int
    var formatCount: Int
    var streamType: String
    var indicatedBitrate: Double?
    var observedBitrate: Double?
    var averageAudioBitrate: Double?
    var audioTrackDataRate: Double?
    var mediaRequests: Int?
    var updatedAt: Date
    /// True when the playing URL is the stream's dedicated audio-only rendition.
    var usingAudioOnlyRendition: Bool
    /// Declared bandwidth of the audio-only rendition, when known.
    var declaredAudioBandwidth: Double?
    /// True when the HLS manifest was inspected for audio-only renditions.
    var manifestChecked: Bool
    /// Number of variants declared by the HLS manifest (nil when not checked).
    var availableVariants: Int?
    /// Decoded audio codec/sample rate/channels, when known.
    var audioFormat: String?
    /// Why the previously tried stream format failed (URLs scrubbed).
    var lastFormatFailure: String?
    /// True when the stream itself provided song info (ID3 metadata).
    var songInfoFromStream: Bool
    /// Which out-of-stream source supplied the current song, when one did.
    /// Distinguishes "nothing publishes this track" from "the stream is quiet".
    var songInfoSource: String?
    /// True when what that source supplied is programme information (a show
    /// name) rather than a track. Kept separate from `songInfoSource` because
    /// naming the source alone reads as "the song came from here", which is
    /// exactly the confusion a show name in the now-playing bar causes.
    var songInfoIsProgrammeOnly: Bool = false
    /// Every out-of-stream source tried on the last lookup, and what it did.
    var songSources: [SongSourceReport] = []
    /// Every stream-format candidate for this station and what became of it.
    var candidates: [StreamCandidateReport] = []
    /// True when playback started at a remembered endpoint rather than the
    /// preferred one. Fast, but it means an early failure can keep a station on
    /// a fallback format indefinitely, so it is surfaced rather than silent.
    var startedAtRememberedEndpoint: Bool = false

    /// Best available single bitrate figure for compact display. Observed
    /// bitrate is intentionally excluded: it reflects the recent download
    /// rate (highest right after playback starts), not audio quality.
    var primaryBitrate: Double? {
        averageAudioBitrate ?? audioTrackDataRate ?? indicatedBitrate ?? declaredAudioBandwidth
    }
}

/// Formats playback diagnostics. Used both for redacted logging and for the
/// in-app diagnostics screen (the app is installed from CI artifacts, so
/// users often have no access to a console).
///
/// SECURITY: output never contains URLs, usernames, passwords or tokens —
/// only the stream file extension and bitrate figures.
enum PlaybackDiagnostics {
    struct EventSample {
        let indicatedBitrate: Double?
        let observedBitrate: Double?
        let averageAudioBitrate: Double?
        let numberOfMediaRequests: Int?
    }

    struct TrackSample {
        let mediaType: String?
        let estimatedDataRate: Double?
    }

    static func makeSample(
        streamExtension: String,
        events: [EventSample],
        tracks: [TrackSample],
        audioFormatDescription: String? = nil
    ) -> StreamDiagnosticsSample {
        var sample = StreamDiagnosticsSample(
            streamExtension: streamExtension.trimmingCharacters(in: .whitespaces),
            indicatedBitrate: nil,
            observedBitrate: nil,
            averageAudioBitrate: nil,
            audioTrackDataRate: nil,
            mediaRequests: nil
        )
        if let last = events.last {
            sample.indicatedBitrate = positive(last.indicatedBitrate)
            sample.observedBitrate = positive(last.observedBitrate)
            sample.averageAudioBitrate = positive(last.averageAudioBitrate)
            sample.mediaRequests = last.numberOfMediaRequests
        }
        if let audioTrack = tracks.first(where: { $0.mediaType == "soun" }) {
            sample.audioTrackDataRate = positive(audioTrack.estimatedDataRate)
        }
        sample.audioFormat = audioFormatDescription
        return sample
    }

    static func summary(for sample: StreamDiagnosticsSample) -> String {
        var parts: [String] = []
        parts.append("streamType=\(sample.streamExtension.isEmpty ? "unknown" : sample.streamExtension)")
        if let bitrate = sample.indicatedBitrate {
            parts.append(String(format: "hlsIndicatedBitrate=%.0fkbps", bitrate / 1000))
        }
        if let bitrate = sample.observedBitrate {
            parts.append(String(format: "observedBitrate=%.0fkbps", bitrate / 1000))
        }
        if let bitrate = sample.averageAudioBitrate {
            parts.append(String(format: "averageAudioBitrate=%.0fkbps", bitrate / 1000))
        }
        if let requests = sample.mediaRequests {
            parts.append("mediaRequests=\(requests)")
        }
        if let rate = sample.audioTrackDataRate {
            parts.append(String(format: "audioTrackDataRate=%.0fkbps", rate / 1000))
        }
        if let format = sample.audioFormat {
            parts.append("audioFormat=\(format)")
        }
        if sample.indicatedBitrate == nil, sample.observedBitrate == nil, sample.averageAudioBitrate == nil {
            parts.append("noAccessLogEvents")
        }
        // Always note that rendition quality is decided by the provider stream.
        parts.append("qualityDeterminedBySource")
        return parts.joined(separator: "; ")
    }

    /// Convenience for callers that have raw samples (kept for tests).
    static func summary(
        streamExtension: String,
        events: [EventSample],
        tracks: [TrackSample]
    ) -> String {
        summary(for: makeSample(streamExtension: streamExtension, events: events, tracks: tracks))
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
