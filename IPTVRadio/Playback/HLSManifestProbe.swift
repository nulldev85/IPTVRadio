import Foundation

/// Result of inspecting an HLS master playlist for a dedicated audio track.
struct HLSProbeResult: Codable, Equatable {
    /// Audio-only rendition URL to prefer for playback, when one exists.
    var audioOnlyURL: URL?
    /// Declared bandwidth of the chosen audio rendition, if present.
    var declaredAudioBandwidth: Double?
    /// Number of variants found in the master playlist.
    var variantCount: Int
    /// Number of dedicated audio renditions (EXT-X-MEDIA TYPE=AUDIO) found.
    var audioRenditionCount: Int
}

/// Parses HLS master playlists to locate the best audio-only rendition.
/// Pure and unit tested; never logs URLs.
enum HLSManifestParser {
    struct Candidate {
        var url: URL
        var bandwidth: Double?
    }

    static func parse(_ text: String, baseURL: URL) -> HLSProbeResult {
        var audioOnlyVariants: [Candidate] = []
        var audioRenditions: [Candidate] = []
        var variantCount = 0
        var audioRenditionCount = 0
        var pendingStreamInf: [String: String]?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingStreamInf = attributes(of: String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
                variantCount += 1
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = attributes(of: String(line.dropFirst("#EXT-X-MEDIA:".count)))
                if attrs["TYPE"]?.uppercased() == "AUDIO" {
                    audioRenditionCount += 1
                    if let uri = attrs["URI"], let url = resolve(uri, base: baseURL) {
                        audioRenditions.append(Candidate(
                            url: url,
                            bandwidth: number(attrs["BANDWIDTH"]) ?? number(attrs["AVERAGE-BANDWIDTH"])
                        ))
                    }
                }
                pendingStreamInf = nil
            } else if line.hasPrefix("#") {
                // Other tags between STREAM-INF and its URI are allowed.
                continue
            } else if let attrs = pendingStreamInf {
                pendingStreamInf = nil
                guard let url = resolve(line, base: baseURL) else { continue }
                if isAudioOnly(codecs: attrs["CODECS"], resolution: attrs["RESOLUTION"]) {
                    audioOnlyVariants.append(Candidate(
                        url: url,
                        bandwidth: number(attrs["AVERAGE-BANDWIDTH"]) ?? number(attrs["BANDWIDTH"])
                    ))
                }
            }
        }

        let candidates = (audioOnlyVariants + audioRenditions)
            .sorted { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }
        let best = candidates.first

        return HLSProbeResult(
            audioOnlyURL: best?.url,
            declaredAudioBandwidth: best?.bandwidth,
            variantCount: variantCount,
            audioRenditionCount: audioRenditionCount
        )
    }

    /// A variant is audio-only when it declares no resolution and its codecs
    /// contain audio codecs but none of the known video codecs. Missing codec
    /// information is treated conservatively (not audio-only).
    static func isAudioOnly(codecs: String?, resolution: String?) -> Bool {
        if let resolution, !resolution.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        guard let codecs, !codecs.isEmpty else { return false }
        let lower = codecs.lowercased()
        let videoHints = ["avc1", "avc3", "hvc1", "hev1", "mp4v", "av01", "vp09", "dvh1", "dvh2"]
        if videoHints.contains(where: { lower.contains($0) }) { return false }
        let audioHints = ["mp4a", "ac-3", "ec-3", "opus", "alac"]
        return audioHints.contains(where: { lower.contains($0) })
    }

    /// Parses `KEY=VALUE` attribute lists; quoted values may contain commas.
    static func attributes(of line: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inQuotes = false
        var readingValue = false

        func commit() {
            let name = key.trimmingCharacters(in: .whitespaces).uppercased()
            if !name.isEmpty { result[name] = value }
            key = ""
            value = ""
            readingValue = false
        }

        for char in line {
            if readingValue {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == ",", !inQuotes {
                    commit()
                } else {
                    value.append(char)
                }
            } else {
                if char == "=" {
                    readingValue = true
                } else if char == "," {
                    key = ""
                } else {
                    key.append(char)
                }
            }
        }
        commit()
        return result
    }

    private static func resolve(_ uri: String, base: URL) -> URL? {
        let trimmed = uri.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    private static func number(_ string: String?) -> Double? {
        guard let string else { return nil }
        return Double(string.trimmingCharacters(in: .whitespaces))
    }
}

/// Fetches and parses an HLS master playlist to find a dedicated audio track.
/// SECURITY: URLs are never logged (they may embed credentials).
struct HLSManifestProbe {
    let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient.providerDefault) {
        self.http = http
    }

    /// Probes an HLS URL. Only `.m3u8` candidates are probed (fetching a raw
    /// `.ts` live stream would hang); failures return nil.
    func probe(url: URL) async -> HLSProbeResult? {
        guard url.pathExtension.lowercased() == "m3u8" else { return nil }
        do {
            let request = RequestBuilder.get(url, timeout: 5)
            let (data, response) = try await http.data(for: request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }
            return HLSManifestParser.parse(text, baseURL: url)
        } catch {
            return nil
        }
    }
}

/// Small session + persisted cache of probe results. Only positive results
/// (an audio-only rendition was found) are persisted so stale negatives are
/// re-checked on later launches.
final class HLSProbeCache {
    private let fileStore: JSONFileStore
    private let filename = "hls-probe-cache.json"
    private let lock = NSLock()
    private var memory: [String: HLSProbeResult]

    init(fileStore: JSONFileStore = JSONFileStore()) {
        self.fileStore = fileStore
        self.memory = fileStore.load([String: HLSProbeResult].self, filename: filename) ?? [:]
    }

    func result(for url: URL) -> HLSProbeResult? {
        lock.lock()
        defer { lock.unlock() }
        return memory[url.absoluteString]
    }

    func store(_ result: HLSProbeResult, for url: URL) {
        lock.lock()
        memory[url.absoluteString] = result
        let positives = memory.filter { $0.value.audioOnlyURL != nil }
        lock.unlock()
        fileStore.save(positives, filename: filename)
    }
}
