import Foundation

/// JSON file persistence helper used for favorites, history and the station cache.
struct JSONFileStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("IPTVRadio", isDirectory: true)
        }
    }

    func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    func save<T: Encodable>(_ value: T, filename: String) {
        do {
            try saveThrowing(value, filename: filename)
        } catch {
            AppLogger.persistence.error("Failed to persist \(filename, privacy: .public)")
        }
    }

    func saveThrowing<T: Encodable>(_ value: T, filename: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url(for: filename), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: filename)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    func remove(filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    /// Approximate size of all stored files in bytes (for cache reporting).
    var totalBytes: Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { sum, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + size
        }
    }
}
