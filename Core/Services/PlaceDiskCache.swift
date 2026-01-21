import Foundation

actor PlaceDiskCache {
    struct Snapshot: Codable {
        let version: Int
        let savedAt: Date
        let places: [Place]
        let communityTopRated: [String: [Place]]?
        let globalDatasetETag: String?
    }

    private enum Constants {
        static let directoryName = "PlaceCache"
        static let filename = "places-v5.json"
        static let legacyFilename = "places-v4.json"
        static let version = 5
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = cachesDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        self.fileURL = directory.appendingPathComponent(Constants.filename)

        encoder = JSONEncoder()
        decoder = JSONDecoder()

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            let legacyURL = directory.appendingPathComponent(Constants.legacyFilename)
            if fileManager.fileExists(atPath: legacyURL.path) {
                try? fileManager.removeItem(at: legacyURL)
            }
        }
    }

    func loadSnapshot() -> Snapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            guard snapshot.version == Constants.version else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
            return snapshot
        } catch {
#if DEBUG
            print("[PlaceDiskCache] Failed to load snapshot:", error)
#endif
            return nil
        }
    }

    func saveSnapshot(
        places: [Place],
        communityTopRated: [String: [Place]]? = nil,
        eTag: String? = nil
    ) {
        guard !places.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        let trimmedCommunity = communityTopRated?.mapValues { Array($0.prefix(20)) }
        let snapshot = Snapshot(
            version: Constants.version,
            savedAt: Date(),
            places: places,
            communityTopRated: trimmedCommunity,
            globalDatasetETag: eTag
        )
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
#if DEBUG
            print("[PlaceDiskCache] Failed to persist snapshot:", error)
#endif
        }
    }
}
