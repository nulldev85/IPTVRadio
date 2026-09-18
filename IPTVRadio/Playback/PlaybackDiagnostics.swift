import Foundation
import AVFoundation

/// A snapshot of stream quality information collected from AVPlayer's access
/// log and the audio track. Contains no URLs or credentials.
struct StreamDiagnosticsSample: Equatable {
    var streamExtension: String
    var indicatedBitrate: Double?
    var observedBitrate: Double?
    var averageAudioBitrate: Double?
    var audioTrackDataRate: Double?
    var mediaRequests: Int?
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

    /// Best available single bitrate figure for compact display.
    var primaryBitrate: Double? {
        averageAudioBitrate ?? audioTrackDataRate ?? indicatedBitrate ?? observedBitrate
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
        tracks: [TrackSample]
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
