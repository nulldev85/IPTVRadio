import Foundation

/// Result of classifying one raw channel.
struct ChannelVerdict: Equatable {
    var radioScore: Int
    var siriusScore: Int
    var isRadio: Bool
    var isSirius: Bool
}

/// Scores channels against configurable rules to detect audio/radio stations
/// and to prioritize SiriusXM-labelled ones.
struct RadioStationDetector: Sendable {
    let rules: RadioDetectionRules

    init(rules: RadioDetectionRules = .default) {
        self.rules = rules
    }

    func classify(_ channel: RawChannel) -> ChannelVerdict {
        let name = channel.name.lowercased()
        let group = channel.group.lowercased()
        let tvg = (channel.tvgID ?? "").lowercased()
        let pathExtension = channel.url.pathExtension.lowercased()

        var score = 0

        // Group signals.
        if containsAny(group, rules.radioGroupKeywords) { score += 3 }
        if containsAny(group, rules.videoGroupKeywords) { score -= 3 }

        // Name signals.
        if containsAny(name, rules.radioNameKeywords) { score += 2 }

        // Extension signals.
        if rules.audioExtensions.contains(pathExtension), !pathExtension.isEmpty { score += 3 }
        if rules.videoExtensions.contains(pathExtension), !pathExtension.isEmpty { score -= 4 }

        // Xtream often marks radio channels with stream metadata via tvg id.
        if tvg.contains("radio") { score += 1 }

        // URL path hints (e.g. /radio/ in the path).
        let path = channel.url.path.lowercased()
        if path.contains("/radio") || path.contains("aac") || path.contains("mp3") { score += 1 }

        let isRadio = score >= rules.minimumRadioScore
        let siriusScore = SiriusMatcher.score(
            name: channel.name,
            group: channel.group,
            tvgID: channel.tvgID,
            keywords: rules.siriusKeywords
        )
        return ChannelVerdict(
            radioScore: score,
            siriusScore: siriusScore,
            isRadio: isRadio,
            isSirius: siriusScore > 0
        )
    }

    /// Runs detection over all channels and produces a deduplicated snapshot.
    func buildSnapshot(
        channels: [RawChannel],
        categoriesByID: [String: ChannelCategory] = [:]
    ) -> LibrarySnapshot {
        var sirius: [RadioStation] = []
        var radio: [RadioStation] = []

        for channel in channels {
            let verdict = classify(channel)
            guard verdict.isRadio || verdict.isSirius else { continue }
            if rules.excludeVideoChannels, !verdict.isRadio, !verdict.isSirius { continue }

            let group = categoryName(for: channel, categoriesByID: categoriesByID)
            let station = RadioStation(
                name: channel.name,
                streamURL: channel.url,
                groupTitle: group,
                logoURL: channel.logoURL,
                tvgID: channel.tvgID,
                source: channel.source
            )
            if verdict.isSirius {
                sirius.append(station)
            } else {
                radio.append(station)
            }
        }

        let dedupedSirius = StationDeduplicator.deduplicate(sirius)
        let dedupedRadio = StationDeduplicator.deduplicate(radio)

        let categoryNames = Set(
            dedupedSirius.map(\.groupTitle) + dedupedRadio.map(\.groupTitle)
        ).filter { !$0.isEmpty }

        let categories = categoryNames
            .map { ChannelCategory(id: StationIdentifier.stableHash("category|\($0)"), name: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return LibrarySnapshot(
            siriusStations: dedupedSirius,
            radioStations: dedupedRadio,
            categories: categories,
            totalChannelsScanned: channels.count,
            generatedAt: Date()
        )
    }

    private func categoryName(for channel: RawChannel, categoriesByID: [String: ChannelCategory]) -> String {
        if let id = channel.categoryID, let category = categoriesByID[id] {
            return category.name
        }
        return channel.group
    }

    private func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        for needle in needles {
            let n = needle.lowercased().trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            if haystack.contains(n) { return true }
        }
        return false
    }
}

/// Scores how strongly a channel looks like a SiriusXM channel.
enum SiriusMatcher {
    /// Weighted keyword score: name matches count most, then group, then tvg-id.
    static func score(name: String, group: String, tvgID: String?, keywords: [String]) -> Int {
        let n = name.lowercased()
        let g = group.lowercased()
        let t = (tvgID ?? "").lowercased()

        var score = 0
        for keyword in keywords {
            let k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            if n.contains(k) {
                score = max(score, 3)
            }
            if g.contains(k) {
                score = max(score, 2)
            }
            if t.contains(k) {
                score = max(score, 1)
            }
        }
        return score
    }
}

/// Removes duplicate stations keyed by stream URL and by normalized name.
enum StationDeduplicator {
    static func deduplicate(_ stations: [RadioStation]) -> [RadioStation] {
        var byURL = [String: RadioStation]()
        var byName = [String: RadioStation]()

        for station in stations {
            let urlKey = normalizedURLKey(station.streamURL)
            let nameKey = normalizedStationName(station.name)

            if var existing = byURL[urlKey] {
                existing = merge(existing, incoming: station)
                byURL[urlKey] = existing
                byName[normalizedStationName(existing.name)] = existing
                continue
            }
            if var existing = byName[nameKey] {
                // Only merge name duplicates when hosts match; different hosts
                // may legitimately carry same-named stations from other sources.
                if existing.streamURL.host == station.streamURL.host {
                    existing = merge(existing, incoming: station)
                    byName[nameKey] = existing
                    byURL[normalizedURLKey(existing.streamURL)] = existing
                    continue
                }
            }
            byURL[urlKey] = station
            byName[nameKey] = station
        }

        // Preserve first-seen order while ensuring uniqueness by URL key.
        var seen = Set<String>()
        var out: [RadioStation] = []
        for station in stations {
            let key = normalizedURLKey(station.streamURL)
            guard seen.insert(key).inserted else { continue }
            if let merged = byURL[key] {
                out.append(merged)
            }
        }
        return out
    }

    static func normalizedURLKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        var string = (components?.url ?? url).absoluteString.lowercased()
        if string.hasSuffix("/") { string.removeLast() }
        return string
    }

    static func normalizedStationName(_ name: String) -> String {
        name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    /// Merges metadata: prefer a non-empty logo, richer group, keep original order.
    private static func merge(_ base: RadioStation, incoming: RadioStation) -> RadioStation {
        var merged = base
        if (merged.logoURL == nil), let logo = incoming.logoURL {
            merged.logoURL = logo
        }
        if merged.groupTitle.isEmpty, !incoming.groupTitle.isEmpty {
            merged.groupTitle = incoming.groupTitle
        }
        if merged.tvgID == nil, let tvg = incoming.tvgID {
            merged.tvgID = tvg
        }
        if merged.name.isEmpty { merged.name = incoming.name }
        return merged
    }
}
