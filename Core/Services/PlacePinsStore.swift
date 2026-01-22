import Foundation
import MapKit
import Combine

@MainActor
final class PlacePinsStore: ObservableObject {
    @Published private(set) var pins: [PlacePin] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var didLoadFromDisk = false

    private let diskCache = PlacePinsDiskCache()
    private let refreshInterval: TimeInterval = 60 * 60 * 24
    private var pinsByID: [UUID: PlacePin] = [:]
    private var refreshTask: Task<Void, Never>?
    private var eTag: String?

    init() {
        Task { await loadFromDisk() }
    }

    func pin(for id: UUID) -> PlacePin? {
        pinsByID[id]
    }

    func refreshIfNeeded(force: Bool = false) {
        if !force, let lastRefresh {
            let age = Date().timeIntervalSince(lastRefresh)
            if age < refreshInterval { return }
        }
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            isRefreshing = true
            lastError = nil
            defer {
                isRefreshing = false
                refreshTask = nil
            }

            do {
                let response = try await PlaceAPI.fetchAllPlacePins(
                    pageSize: 1000,
                    ifNoneMatch: eTag
                )

                if response.notModified {
                    lastRefresh = Date()
                    lastError = nil
                    return
                }

                let newPins = response.pins.map(PlacePin.init(dto:))
                updatePins(newPins, eTag: response.eTag)
                lastRefresh = Date()
                lastError = nil
                await diskCache.saveSnapshot(pins: newPins, eTag: response.eTag)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func visiblePins(in region: MKCoordinateRegion) -> [PlacePin] {
        let bbox = region.bbox
        return pins.filter { pin in
            pin.latitude >= bbox.south && pin.latitude <= bbox.north &&
                pin.longitude >= bbox.west && pin.longitude <= bbox.east
        }
    }

    private func loadFromDisk() async {
        defer { didLoadFromDisk = true }
        if let snapshot = await diskCache.loadSnapshot() {
            updatePins(snapshot.pins, eTag: snapshot.eTag)
            lastRefresh = snapshot.savedAt
            if !snapshot.pins.isEmpty, snapshot.pins.allSatisfy({ $0.address == nil }) {
                refresh()
            }
        }
    }

    private func updatePins(_ newPins: [PlacePin], eTag: String?) {
        pins = newPins
        pinsByID = Dictionary(uniqueKeysWithValues: newPins.map { ($0.id, $0) })
        if let eTag {
            self.eTag = eTag
        }
    }
}
