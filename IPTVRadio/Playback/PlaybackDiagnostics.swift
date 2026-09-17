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
