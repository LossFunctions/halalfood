import Foundation

actor PlacePinsDiskCache {
    struct Snapshot: Codable {
        let version: Int
        let savedAt: Date
        let pins: [PlacePin]
        let eTag: String?
    }

    private enum Constants {
        static let directoryName = "PlacePins"
        static let filename = "pins-v2.json"
        static let version = 2
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static func cachedSnapshotExists(fileManager: FileManager = .default) -> Bool {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        let fileURL = directory.appendingPathComponent(Constants.filename)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        self.fileURL = directory.appendingPathComponent(Constants.filename)

        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

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
            print("[PlacePinsDiskCache] Failed to load snapshot:", error)
#endif
            return nil
        }
    }

    func saveSnapshot(pins: [PlacePin], eTag: String?) {
        guard !pins.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }
        let snapshot = Snapshot(
            version: Constants.version,
            savedAt: Date(),
            pins: pins,
            eTag: eTag
        )
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
#if DEBUG
            print("[PlacePinsDiskCache] Failed to persist snapshot:", error)
#endif
        }
    }
}
