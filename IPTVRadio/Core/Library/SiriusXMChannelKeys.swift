import Foundation

/// Maps a station's display name to the channel key broadcaster metadata
/// services use for it.
///
/// This table exists because deriving the key from the panel's label does not
/// work, and on device it produced nothing but 404s. The two names are related
/// but not by any rule: "Fly" is keyed `siriusxmfly` while "Shade 45" is
/// `shade45`; "2000s" is `pop2k`; "Rock The Bells" is `rockthebellsradio`. No
/// amount of stripping and re-prefixing gets from one to the other reliably, so
/// the known channels are simply listed, and derivation is kept only as a
/// fallback for channels not in the list.
///
/// Best effort, not authoritative: these keys are not published as a spec, and
/// a wrong entry costs one failed request that the derived shapes then follow.
/// Adding a channel is a one-line change, and a listener can override the key
/// per station from the diagnostics screen when a lookup is not matching.
enum SiriusXMChannelKeys {
    /// Display name → channel key. Names are matched after normalisation, so
    /// case, punctuation and the SiriusXM brand prefix do not matter here.
    static let table: [String: String] = [
        // Decades
        "60s on 6": "60son6",
        "70s on 7": "70son7",
        "80s on 8": "80son8",
        "90s on 9": "90son9",
        "Pop2K": "pop2k",
        "2000s": "pop2k",
        "Hits 1": "siriusxmhits1",
        "Fly": "siriusxmfly",
        "The Pulse": "thepulse",
        "The Blend": "theblend",
        "Venus": "venus",
        "Love": "siriusxmlove",
        "Pandora Now": "pandoranow",

        // Rock
        "Octane": "octane",
        "Ozzy's Boneyard": "ozzysboneyard",
        "Hair Nation": "hairnation",
        "Liquid Metal": "liquidmetal",
        "Turbo": "turbo",
        "Classic Rewind": "classicrewind",
        "Classic Vinyl": "classicvinyl",
        "Deep Tracks": "deeptracks",
        "The Spectrum": "thespectrum",
        "Alt Nation": "altnation",
        "Lithium": "lithium",
        "1st Wave": "1stwave",
        "Underground Garage": "undergroundgarage",
        "Yacht Rock Radio": "yachtrockradio",
        "The Beatles Channel": "thebeatleschannel",
        "E Street Radio": "estreetradio",
        "Tom Petty Radio": "tompettyradio",
        "Pearl Jam Radio": "pearljamradio",

        // Hip-hop and R&B
        "Shade 45": "shade45",
        "Hip-Hop Nation": "hiphopnation",
        "Rock The Bells": "rockthebellsradio",
        "Backspin": "backspin",
        "The Heat": "theheat",
        "The Groove": "thegroove",
        "Soul Town": "soultown",
        "Heart & Soul": "heartandsoul",
        "The Joint": "thejoint",

        // Country
        "The Highway": "thehighway",
        "Prime Country": "primecountry",
        "Willie's Roadhouse": "williesroadhouse",
        "Outlaw Country": "outlawcountry",
        "Y2Kountry": "y2kountry",
        "Bluegrass Junction": "bluegrassjunction",
        "The Village": "thevillage",

        // Dance and electronic
        "BPM": "bpm",
        "Utopia": "utopia",
        "Diplo's Revolution": "diplosrevolution",
        "Studio 54 Radio": "studio54radio",
        "Chill": "chill",

        // Jazz, classical, easy
        "Symphony Hall": "symphonyhall",
        "Real Jazz": "realjazz",
        "Watercolors": "watercolors",
        "Spa": "spa",
        "Escape": "escape",
        "The Bridge": "thebridge",
        "Coffee House": "coffeehouse",

        // Latin and faith
        "Caliente": "caliente",
        "Flow Nación": "flownacion",
        "The Message": "themessage",
        "Kirk Franklin's Praise": "kirkfranklinspraise"
    ]

    /// Normalised table, built once: normalised display name → key.
    private static let normalised: [String: String] = {
        var map: [String: String] = [:]
        for (name, key) in table {
            map[normalise(name)] = key
        }
        return map
    }()

    /// Table names long enough to be matched by containment, longest first.
    ///
    /// Longest first so the most specific channel wins when a label contains
    /// more than one ("Outlaw Country" contains "country", which also belongs
    /// to "Prime Country"). Short names are excluded entirely rather than
    /// ranked, because containment on them is a coin flip: "spa", "love" and
    /// "bpm" appear inside plenty of unrelated station names, so those channels
    /// are matched only when the whole name is theirs.
    private static let containable: [(normalised: String, key: String)] = {
        normalised
            .filter { $0.key.count >= 6 }
            .map { (normalised: $0.key, key: $0.value) }
            .sorted { $0.normalised.count > $1.normalised.count }
    }()

    /// The channel key for a station name, when it is a channel we know.
    ///
    /// A panel labels the same channel "Fly", "Radio: SiriusXM FLY" and "USA:
    /// SXM Fly HD", so the name is matched in several spellings: as given, with
    /// the section label and quality suffix removed, and with the brand removed
    /// as well. Exact matches are tried on all of them before falling back to
    /// containment, which is restricted to names of six characters or more —
    /// containment on "spa" or "bpm" would match unrelated stations.
    static func key(forStationNamed name: String) -> String? {
        let undecorated = strippingDecorations(name)
        let spellings = [name, undecorated].flatMap { [$0, strippingBrand($0)] }
        for spelling in spellings {
            let cleaned = normalise(spelling)
            guard !cleaned.isEmpty else { continue }
            if let exact = normalised[cleaned] { return exact }
        }
        let cleaned = normalise(undecorated)
        guard !cleaned.isEmpty else { return nil }
        for candidate in containable where cleaned.contains(candidate.normalised) {
            return candidate.key
        }
        return nil
    }

    /// Removes the decorations panels add around a channel name.
    ///
    /// Lists are labelled for browsing, not for lookups: "Radio: SiriusXM FLY",
    /// "USA MUSIC: Octane HD". A short section prefix before a colon and a
    /// quality suffix are noise for every one of them.
    ///
    /// Short is the safeguard on the prefix: a wrong strip does not just add a
    /// useless attempt, it removes the only name that could have matched, so a
    /// long prefix is left alone.
    static func strippingDecorations(_ stationName: String) -> String {
        var text = stationName
        if let colon = text.firstIndex(of: ":") {
            let label = text[..<colon]
            // Taken even when the remainder is empty: a name that is nothing
            // but a section label ("Radio:") names no channel.
            if label.count <= 12 {
                text = String(text[text.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        text = text
            .replacingOccurrences(of: "Radio -", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Quality tags only. "Radio" is deliberately not in this list: it is
        // part of plenty of real channel names ("E Street Radio"), and
        // stripping it would leave the actual name untried.
        for suffix in ["FHD", "UHD", "HD", "SD"] {
            if text.count > suffix.count,
               text.lowercased().hasSuffix(" " + suffix.lowercased()) {
                text = String(text.dropLast(suffix.count + 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    static func strippingBrand(_ text: String) -> String {
        text
            .replacingOccurrences(of: "SiriusXM", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "SXM", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased alphanumerics only: drops case, spaces, punctuation and
    /// accents, so "Flow Nación" and "FLOW NACION" reduce alike.
    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
    }
}
