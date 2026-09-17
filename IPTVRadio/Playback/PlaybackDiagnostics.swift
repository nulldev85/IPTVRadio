import Foundation
import AVFoundation

/// Formats playback diagnostics for logging.
///
/// SECURITY: output never contains URLs, usernames, passwords or tokens —
/// only the stream file extension and bitrate figures. This makes it possible
/// to distinguish provider source quality (e.g. a 64 kbps radio stream) from
/// app-side playback problems on a physical device.
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
        let codec: String?
        let sampleRate: Double?
        let channelCount: Int?

        init(
            mediaType: String?,
            estimatedDataRate: Double?,
            codec: String? = nil,
            sampleRate: Double? = nil,
            channelCount: Int? = nil
        ) {
            self.mediaType = mediaType
            self.estimatedDataRate = estimatedDataRate
            self.codec = codec
            self.sampleRate = sampleRate
            self.channelCount = channelCount
        }
    }

    /// Live, UI-facing snapshot shown in the in-app diagnostics panel.
    /// SECURITY: never carries a URL, username, password or token — only
    /// format/codec/bitrate figures and whether a direct source was used.
    struct Snapshot: Equatable {
        var streamExtension: String
        var usesDirectSource: Bool
        var indicatedBitrate: Double?
        var observedBitrate: Double?
        var averageAudioBitrate: Double?
        var codec: String?
        var sampleRate: Double?
        var channelCount: Int?
        var numberOfMediaRequests: Int?
        var capturedAt: Date
    }

    static func snapshot(
        streamExtension: String,
        usesDirectSource: Bool,
        events: [EventSample],
        tracks: [TrackSample],
        capturedAt: Date = Date()
    ) -> Snapshot {
        let last = events.last
        let audioTrack = tracks.first { $0.mediaType == "soun" }
        return Snapshot(
            streamExtension: streamExtension.isEmpty ? "unknown" : streamExtension,
            usesDirectSource: usesDirectSource,
            indicatedBitrate: last?.indicatedBitrate,
            observedBitrate: last?.observedBitrate,
            averageAudioBitrate: last?.averageAudioBitrate,
            codec: audioTrack?.codec,
            sampleRate: audioTrack?.sampleRate,
            channelCount: audioTrack?.channelCount,
            numberOfMediaRequests: last?.numberOfMediaRequests,
            capturedAt: capturedAt
        )
    }

    static func summary(
        streamExtension: String,
        events: [EventSample],
        tracks: [TrackSample]
    ) -> String {
        var parts: [String] = []
        let ext = streamExtension.trimmingCharacters(in: .whitespaces)
        parts.append("streamType=\(ext.isEmpty ? "unknown" : ext)")

        if let last = events.last {
            if let bitrate = last.indicatedBitrate, bitrate > 0 {
                parts.append(String(format: "hlsIndicatedBitrate=%.0fkbps", bitrate / 1000))
            }
            if let bitrate = last.observedBitrate, bitrate > 0 {
                parts.append(String(format: "observedBitrate=%.0fkbps", bitrate / 1000))
            }
            if let bitrate = last.averageAudioBitrate, bitrate > 0 {
                parts.append(String(format: "averageAudioBitrate=%.0fkbps", bitrate / 1000))
            }
            if let requests = last.numberOfMediaRequests {
                parts.append("mediaRequests=\(requests)")
            }
        } else {
            parts.append("noAccessLogEvents")
        }

        if let audioTrack = tracks.first(where: { $0.mediaType == "soun" }),
           let rate = audioTrack.estimatedDataRate, rate > 0 {
            parts.append(String(format: "audioTrackDataRate=%.0fkbps", rate / 1000))
        }

        // Always note that rendition quality is decided by the provider stream.
        parts.append("qualityDeterminedBySource")
        return parts.joined(separator: "; ")
    }
}
