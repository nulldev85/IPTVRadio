import Foundation

// MARK: - Lenient decoding helpers
// Xtream deployments vary wildly: numbers arrive as strings, strings as
// numbers, and nulls everywhere. These helpers never throw on type mismatch.

enum Lenient {
    static func string(_ container: KeyedDecodingContainer<XtreamCodingKey>, _ key: XtreamCodingKey) -> String? {
        if let v = try? container.decode(String.self, forKey: key) { return v }
        if let v = try? container.decode(Int.self, forKey: key) { return String(v) }
        if let v = try? container.decode(Double.self, forKey: key) {
            return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
        }
        if let v = try? container.decode(Bool.self, forKey: key) { return v ? "1" : "0" }
        return nil
    }

    static func int(_ container: KeyedDecodingContainer<XtreamCodingKey>, _ key: XtreamCodingKey) -> Int? {
        if let v = try? container.decode(Int.self, forKey: key) { return v }
        if let v = try? container.decode(String.self, forKey: key) { return Int(v.trimmingCharacters(in: .whitespaces)) }
        if let v = try? container.decode(Double.self, forKey: key) { return Int(v) }
        if let v = try? container.decode(Bool.self, forKey: key) { return v ? 1 : 0 }
        return nil
    }

    static func double(_ container: KeyedDecodingContainer<XtreamCodingKey>, _ key: XtreamCodingKey) -> Double? {
        if let v = try? container.decode(Double.self, forKey: key) { return v }
        if let v = try? container.decode(String.self, forKey: key) { return Double(v) }
        if let v = try? container.decode(Int.self, forKey: key) { return Double(v) }
        return nil
    }

    static func url(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme, !scheme.isEmpty,
              url.host != nil else { return nil }
        return url
    }
}

/// A string-or-int coding key usable with the lenient helpers.
struct XtreamCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    static let num = XtreamCodingKey(stringValue: "num")
    static let name = XtreamCodingKey(stringValue: "name")
    static let streamType = XtreamCodingKey(stringValue: "stream_type")
    static let streamID = XtreamCodingKey(stringValue: "stream_id")
    static let streamIcon = XtreamCodingKey(stringValue: "stream_icon")
    static let epgChannelID = XtreamCodingKey(stringValue: "epg_channel_id")
    static let categoryID = XtreamCodingKey(stringValue: "category_id")
    static let directSource = XtreamCodingKey(stringValue: "direct_source")
    static let containerExtension = XtreamCodingKey(stringValue: "container_extension")
    static let categoryIDAlt = XtreamCodingKey(stringValue: "category_id")
}

// MARK: - Wire models

/// `user_info` object from the Xtream auth response.
struct XtreamUserInfo: Decodable, Equatable {
    var auth: Int?
    var status: String?
    var username: String?
    var expDate: String?
    var maxConnections: String?
    var activeConnections: String?
    var isTrial: String?

    init(auth: Int?, status: String?, username: String?, expDate: String?, maxConnections: String?, activeConnections: String?, isTrial: String?) {
        self.auth = auth
        self.status = status
        self.username = username
        self.expDate = expDate
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
        self.isTrial = isTrial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: XtreamCodingKey.self)
        auth = Lenient.int(c, .init(stringValue: "auth"))
        status = Lenient.string(c, .init(stringValue: "status"))
        username = Lenient.string(c, .init(stringValue: "username"))
        expDate = Lenient.string(c, .init(stringValue: "exp_date"))
        maxConnections = Lenient.string(c, .init(stringValue: "max_connections"))
        activeConnections = Lenient.string(c, .init(stringValue: "active_cons"))
        isTrial = Lenient.string(c, .init(stringValue: "is_trial"))
    }
}

/// `server_info` object from the Xtream auth response.
struct XtreamServerInfo: Decodable, Equatable {
    var url: String?
    var port: String?
    var httpsPort: String?
    var serverProtocol: String?
    var timezone: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: XtreamCodingKey.self)
        url = Lenient.string(c, .init(stringValue: "url"))
        port = Lenient.string(c, .init(stringValue: "port"))
        httpsPort = Lenient.string(c, .init(stringValue: "https_port"))
        serverProtocol = Lenient.string(c, .init(stringValue: "server_protocol"))
        timezone = Lenient.string(c, .init(stringValue: "timezone"))
    }
}

struct XtreamAuthResponse: Decodable, Equatable {
    var userInfo: XtreamUserInfo?
    var serverInfo: XtreamServerInfo?

    init(userInfo: XtreamUserInfo?, serverInfo: XtreamServerInfo?) {
        self.userInfo = userInfo
        self.serverInfo = serverInfo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: XtreamCodingKey.self)
        userInfo = try? c.decode(XtreamUserInfo.self, forKey: .init(stringValue: "user_info"))
        serverInfo = try? c.decode(XtreamServerInfo.self, forKey: .init(stringValue: "server_info"))
    }
}

struct XtreamLiveCategory: Decodable, Equatable {
    var categoryID: String
    var categoryName: String
    var parentID: String?

    init(categoryID: String, categoryName: String, parentID: String?) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.parentID = parentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: XtreamCodingKey.self)
        categoryID = Lenient.string(c, .categoryID) ?? ""
        categoryName = Lenient.string(c, .init(stringValue: "category_name")) ?? ""
        parentID = Lenient.string(c, .init(stringValue: "parent_id"))
    }
}

struct XtreamLiveStream: Decodable, Equatable {
    var num: String?
    var name: String
    var streamType: String?
    var streamID: String
    var streamIcon: String?
    var epgChannelID: String?
    var categoryID: String?
    var directSource: String?
    /// Provider-declared container for this specific stream (e.g. "ts",
    /// "m3u8", "mp3"). Some Xtream panels transcode `/live/….m3u8` to a
    /// fixed, often low, audio bitrate while `.ts` is served as a direct
    /// passthrough of the source feed — so this field, not a hardcoded
    /// extension, should decide which endpoint format is requested.
    var containerExtension: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: XtreamCodingKey.self)
        num = Lenient.string(c, .num)
        name = Lenient.string(c, .name) ?? ""
        streamType = Lenient.string(c, .streamType)
        streamID = Lenient.string(c, .streamID) ?? ""
        streamIcon = Lenient.string(c, .streamIcon)
        epgChannelID = Lenient.string(c, .epgChannelID)
        categoryID = Lenient.string(c, .categoryID)
        directSource = Lenient.string(c, .directSource)
        containerExtension = Lenient.string(c, .containerExtension)
    }
}

// MARK: - Decoding entry points

enum XtreamDecoder {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func decodeAuth(_ data: Data) throws -> XtreamAuthResponse {
        do {
            return try decoder.decode(XtreamAuthResponse.self, from: data)
        } catch {
            throw ProviderError.malformedResponse("Authentication response was not valid JSON.")
        }
    }

    static func decodeCategories(_ data: Data) throws -> [XtreamLiveCategory] {
        do {
            return try decoder.decode([XtreamLiveCategory].self, from: data)
        } catch {
            throw ProviderError.malformedResponse("Category list was not valid JSON.")
        }
    }

    static func decodeLiveStreams(_ data: Data) throws -> [XtreamLiveStream] {
        do {
            return try decoder.decode([XtreamLiveStream].self, from: data)
        } catch {
            throw ProviderError.malformedResponse("Channel list was not valid JSON.")
        }
    }
}

// MARK: - Session mapping

extension SessionInfo {
    /// Maps a decoded auth response into a normalized session, preferring the
    /// HTTPS port reported by the server when available.
    init(authResponse: XtreamAuthResponse, fallbackBase: URL?) {
        let info = authResponse.userInfo
        let server = authResponse.serverInfo

        var base: URL? = fallbackBase
        if let host = server?.url, !host.isEmpty {
            let httpsPort = server?.httpsPort
            let port = server?.port
            // Prefer HTTPS when the server advertises an HTTPS port.
            if let https = httpsPort, Int(https) ?? 0 > 0 {
                base = URL(string: "https://\(host):\(https)")
            }
            if base == nil, let p = port, Int(p) ?? 0 > 0 {
                base = URL(string: "http://\(host):\(p)")
            }
            if base == nil {
                base = URL(string: "https://\(host)")
            }
        }

        let expDate: Date?
        if let raw = info?.expDate, let epoch = TimeInterval(raw) {
            expDate = Date(timeIntervalSince1970: epoch)
        } else {
            expDate = nil
        }

        self.init(
            isAuthenticated: (info?.auth ?? 0) == 1,
            status: info?.status,
            expiryDate: expDate,
            maxConnections: info?.maxConnections.flatMap { Int($0) },
            activeConnections: info?.activeConnections.flatMap { Int($0) },
            serverURL: base,
            usesInsecureHTTP: base?.scheme?.lowercased() == "http"
        )
    }
}
