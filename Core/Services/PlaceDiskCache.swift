import Foundation

actor PlaceDiskCache {
    struct Snapshot: Codable {
        let version: Int
        let savedAt: Date
        let places: [Place]
    }

    private enum Constants {
        static let directoryName = "PlaceCache"
        static let filename = "places-v1.json"
        static let version = 1
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
        }
    }

    func loadSnapshot() -> Snapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            guard snapshot.version == Constants.version else { return nil }
            return snapshot
        } catch {
#if DEBUG
            print("[PlaceDiskCache] Failed to load snapshot:", error)
#endif
            return nil
        }
    }

    func saveSnapshot(places: [Place]) {
        guard !places.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }

        let snapshot = Snapshot(version: Constants.version, savedAt: Date(), places: places)
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
