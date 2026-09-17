import Foundation

/// User-configurable heuristics for deciding which channels are radio/audio
/// stations and which ones should be treated as SiriusXM channels first.
///
/// Providers label channels very differently, so every keyword list is
/// editable in Settings and persisted locally.
struct RadioDetectionRules: Codable, Hashable {
    /// Group titles indicating radio/audio (e.g. "Radio", "Music", "SiriusXM").
    var radioGroupKeywords: [String]
    /// Group titles indicating video (e.g. "Movies", "Series", "TV").
    var videoGroupKeywords: [String]
    /// Channel-name keywords indicating audio (e.g. "FM", "Radio", "SX", genre words).
    var radioNameKeywords: [String]
    /// File extensions that imply an audio stream.
    var audioExtensions: [String]
    /// File extensions that imply a video stream.
    var videoExtensions: [String]
    /// Total score a channel must reach to be classified as radio.
    var minimumRadioScore: Int
    /// Case-insensitive keywords that mark a station as SiriusXM-focused.
    var siriusKeywords: [String]
    /// When true, non-radio channels are never shown even in "all stations".
    var excludeVideoChannels: Bool

    static let `default` = RadioDetectionRules(
        radioGroupKeywords: [
            "radio", "sirius", "siriusxm", "sxm", "music", "audio", "fm", "am",
            "genre", "talk", "news radio", "stations",
        ],
        videoGroupKeywords: [
            "movie", "movies", "series", "serie", "tv", "television", "vod", "4k",
            "sports", "sport", "kids", "documentary", "cinema", "ppv", "24/7", "shows",
        ],
        radioNameKeywords: [
            "radio", "fm", "am ", "siriusxm", "sirius xm", "sirius", "sxm", "hits",
            "country", "rock", "pop", "jazz", "blues", "classical", "hip hop", "rap",
            "reggae", "latin", "dance", "electronic", "edm", "metal", "punk", "oldies",
            "gospel", "talk", "news", "sports radio", "classics", "top 40", "ac",
            "christian", "k-pop", "kpop", "salsa", "cumbia", "banda", "reggaeton",
            "musica", "música", "smooth", "swing", "opera", "trance", "house",
        ],
        audioExtensions: ["mp3", "aac", "aacp", "m3u8", "m3u", "pls", "ogg", "opus", "oga", "wav", "flac", "aiff", "aif", "wma"],
        videoExtensions: ["mp4", "mkv", "avi", "mov", "ts", "m2ts", "mts", "flv", "webm", "wmv", "mpg", "mpeg", "m4v", "3gp"],
        minimumRadioScore: 2,
        siriusKeywords: ["siriusxm", "sirius xm", "sirius", "sxm"],
        excludeVideoChannels: true
    )

    enum CodingKeys: String, CodingKey {
        case radioGroupKeywords
        case videoGroupKeywords
        case radioNameKeywords
        case audioExtensions
        case videoExtensions
        case minimumRadioScore
        case siriusKeywords
        case excludeVideoChannels
    }

    init(
        radioGroupKeywords: [String],
        videoGroupKeywords: [String],
        radioNameKeywords: [String],
        audioExtensions: [String],
        videoExtensions: [String],
        minimumRadioScore: Int,
        siriusKeywords: [String],
        excludeVideoChannels: Bool
    ) {
        self.radioGroupKeywords = radioGroupKeywords
        self.videoGroupKeywords = videoGroupKeywords
        self.radioNameKeywords = radioNameKeywords
        self.audioExtensions = audioExtensions
        self.videoExtensions = videoExtensions
        self.minimumRadioScore = minimumRadioScore
        self.siriusKeywords = siriusKeywords
        self.excludeVideoChannels = excludeVideoChannels
    }

    /// Tolerant decoding: fills missing keys with defaults so older caches load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radioGroupKeywords = try c.decodeIfPresent([String].self, forKey: .radioGroupKeywords) ?? Self.default.radioGroupKeywords
        videoGroupKeywords = try c.decodeIfPresent([String].self, forKey: .videoGroupKeywords) ?? Self.default.videoGroupKeywords
        radioNameKeywords = try c.decodeIfPresent([String].self, forKey: .radioNameKeywords) ?? Self.default.radioNameKeywords
        audioExtensions = try c.decodeIfPresent([String].self, forKey: .audioExtensions) ?? Self.default.audioExtensions
        videoExtensions = try c.decodeIfPresent([String].self, forKey: .videoExtensions) ?? Self.default.videoExtensions
        minimumRadioScore = try c.decodeIfPresent(Int.self, forKey: .minimumRadioScore) ?? Self.default.minimumRadioScore
        siriusKeywords = try c.decodeIfPresent([String].self, forKey: .siriusKeywords) ?? Self.default.siriusKeywords
        excludeVideoChannels = try c.decodeIfPresent(Bool.self, forKey: .excludeVideoChannels) ?? Self.default.excludeVideoChannels
    }
}
