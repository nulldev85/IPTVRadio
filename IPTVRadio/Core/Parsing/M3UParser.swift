import Foundation

/// A single entry parsed out of an M3U playlist.
struct M3UItem: Equatable, Sendable {
    var name: String
    var url: URL
    var groupTitle: String
    var tvgID: String?
    var tvgName: String?
    var logoURL: URL?
    var duration: Double?
}

/// Tolerant M3U/M3U8 playlist parser.
///
/// Handles CRLF, BOM, `#EXTGRP`, quoted and unquoted attributes, attribute
/// values containing commas, malformed entries and very large playlists
/// (linear single pass, no fancy regex backtracking).
enum M3UParser {
    /// Parses playlist text into raw M3U items. Entries with unparseable URLs
    /// are skipped; the parse itself never throws unless there is nothing at all.
    static func parse(_ text: String) -> [M3UItem] {
        var cleaned = text
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned.removeFirst()
        }
        var items: [M3UItem] = []
        var pendingMetadata: (name: String, group: String, tvgID: String?, tvgName: String?, logo: URL?, duration: Double?)?
        var pendingGroup: String?

        var iterator = cleaned.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        while let rawLine = iterator.next() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix("\r") { line.removeLast() }
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF") {
                pendingMetadata = parseExtInf(line)
            } else if line.hasPrefix("#EXTGRP") {
                let group = extractAfterColon(line)
                if !group.isEmpty { pendingGroup = group }
            } else if line.hasPrefix("#") {
                // Other directives (PLAYLIST, EXTINF variants, KODIPROP...) ignored.
                continue
            } else {
                // URL line.
                guard let url = Lenient.url(line) else {
                    pendingMetadata = nil
                    pendingGroup = nil
                    continue
                }
                var group = pendingMetadata?.group ?? ""
                if group.isEmpty, let g = pendingGroup { group = g }
                let item = M3UItem(
                    name: pendingMetadata?.name ?? fallbackName(from: url),
                    url: url,
                    groupTitle: group,
                    tvgID: pendingMetadata?.tvgID,
                    tvgName: pendingMetadata?.tvgName,
                    logoURL: pendingMetadata?.logo,
                    duration: pendingMetadata?.duration
                )
                items.append(item)
                pendingMetadata = nil
                pendingGroup = nil
            }
        }
        return items
    }

    /// Parses `#EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="z",Display Name`.
    static func parseExtInf(_ line: String) -> (name: String, group: String, tvgID: String?, tvgName: String?, logo: URL?, duration: Double?)? {
        guard line.lowercased().hasPrefix("#extinf") else { return nil }
        let colonIndex = line.firstIndex(of: ":") ?? line.startIndex
        let after = String(line[line.index(after: colonIndex)...])

        // Split duration (and any leading flags) from the rest at the first comma
        // that is outside quotes.
        let (attributePart, displayName) = splitAttributesAndName(after)

        let duration: Double? = {
            let head = attributePart.split(separator: ",", maxSplits: 1).first.map(String.init) ?? attributePart
            return Double(head.trimmingCharacters(in: .whitespaces))
        }()

        let attrs = parseAttributes(attributePart)
        let tvgID = attrs["tvg-id"]
        let tvgName = attrs["tvg-name"]
        let group = attrs["group-title"] ?? ""
        let logo = Lenient.url(attrs["tvg-logo"])

        let name = displayName.isEmpty ? (tvgName ?? "") : displayName
        guard !name.isEmpty || !attributePart.isEmpty else { return nil }
        return (name, group, tvgID, tvgName, logo, duration)
    }

    /// Splits "#EXTINF:<rest>" payload into attribute chunk and display name at
    /// the first comma outside double quotes.
    static func splitAttributesAndName(_ payload: String) -> (String, String) {
        var inQuotes = false
        for (index, char) in payload.enumerated() {
            if char == "\"" { inQuotes.toggle() }
            if char == ",", !inQuotes {
                let attributes = String(payload.prefix(index))
                let name = String(payload.dropFirst(index + 1)).trimmingCharacters(in: .whitespaces)
                return (attributes, name)
            }
        }
        return (payload, "")
    }

    /// Parses `key="value"` and bare `key=value` pairs.
    static func parseAttributes(_ chunk: String) -> [String: String] {
        var attrs: [String: String] = [:]
        var key = ""
        var value = ""
        var state: ParseState = .key
        var inQuotes = false

        func commit() {
            let k = key.trimmingCharacters(in: .whitespaces).lowercased()
            if !k.isEmpty { attrs[k] = value }
            key = ""
            value = ""
        }

        for char in chunk {
            switch state {
            case .key:
                if char == "=" {
                    state = .value
                } else if char == " " {
                    commit()
                } else {
                    key.append(char)
                }
            case .value:
                if inQuotes {
                    if char == "\"" {
                        inQuotes = false
                        commit()
                        state = .key
                    } else {
                        value.append(char)
                    }
                } else if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    commit()
                    state = .key
                } else if char == " " {
                    commit()
                    state = .key
                } else {
                    value.append(char)
                }
            }
        }
        commit()
        return attrs
    }

    private enum ParseState { case key, value }

    private static func extractAfterColon(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func fallbackName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }
}
