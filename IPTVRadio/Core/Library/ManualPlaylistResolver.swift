import Foundation

/// Resolves single-station M3U and PLS links to streams VLC can play directly.
/// HLS (.m3u8), MP3, AAC, Ogg, FLAC, and extensionless stream URLs pass through.
struct ManualPlaylistResolver {
    let httpClient: HTTPClient

    static func validHTTPURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    func resolve(_ url: URL) async throws -> [URL] {
        let ext = url.pathExtension.lowercased()
        guard ext == "m3u" || ext == "pls" else { return [url] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("audio/x-mpegurl, audio/x-scpls, text/plain", forHTTPHeaderField: "Accept")
        let result: (Data, HTTPURLResponse)
        do {
            result = try await httpClient.data(for: request)
        } catch {
            throw ManualStationError.playlistUnavailable
        }
        let (data, response) = result
        guard (200..<300).contains(response.statusCode) else {
            throw ManualStationError.playlistUnavailable
        }
        guard data.count <= 1_000_000 else { throw ManualStationError.playlistTooLarge }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ManualStationError.playlistEmpty
        }
        let base = response.url ?? url
        let rawURLs: [String]
        if ext == "pls" {
            rawURLs = text.components(separatedBy: .newlines)
                .compactMap { line -> (Int, String)? in
                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2,
                          parts[0].lowercased().hasPrefix("file"),
                          let index = Int(String(parts[0].dropFirst(4)).trimmingCharacters(in: .whitespaces)) else {
                        return nil
                    }
                    return (index, parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        } else {
            rawURLs = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        var seen = Set<String>()
        let urls = rawURLs.compactMap { raw -> URL? in
            guard let candidate = URL(string: raw, relativeTo: base)?.absoluteURL,
                  let valid = Self.validHTTPURL(candidate.absoluteString),
                  seen.insert(valid.absoluteString).inserted else { return nil }
            return valid
        }
        guard !urls.isEmpty else { throw ManualStationError.playlistEmpty }
        return urls
    }
}
