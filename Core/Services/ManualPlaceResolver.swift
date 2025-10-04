import Foundation
import MapKit

private struct ManualPlaceDefinition {
    let id: UUID
    let name: String
    let anchorCoordinate: CLLocationCoordinate2D
    let halalStatus: Place.HalalStatus
    let rating: Double?
    let ratingCount: Int?
    let confidence: Double?
    let fallbackAddress: String?
    let searchQuery: String
    let searchSpan: MKCoordinateSpan
    let allowsBroadSearch: Bool

    init(id: UUID,
         name: String,
         anchorCoordinate: CLLocationCoordinate2D,
         halalStatus: Place.HalalStatus,
         rating: Double?,
         ratingCount: Int?,
         confidence: Double?,
         fallbackAddress: String?,
         searchQuery: String? = nil,
         searchSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18),
         allowsBroadSearch: Bool = true) {
        self.id = id
        self.name = name
        self.anchorCoordinate = anchorCoordinate
        self.halalStatus = halalStatus
        self.rating = rating
        self.ratingCount = ratingCount
        self.confidence = confidence
        self.fallbackAddress = fallbackAddress
        self.searchQuery = searchQuery ?? name
        self.searchSpan = searchSpan
        self.allowsBroadSearch = allowsBroadSearch
    }

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalizedQuery = PlaceOverrides.normalizedName(for: trimmed)
        guard !normalizedQuery.isEmpty else { return false }

        let normalizedName = PlaceOverrides.normalizedName(for: name)
        if normalizedName.contains(normalizedQuery) { return true }

        if let fallbackAddress {
            let normalizedAddress = PlaceOverrides.normalizedName(for: fallbackAddress)
            if normalizedAddress.contains(normalizedQuery) { return true }
        }
        return false
    }

    func searchRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(center: anchorCoordinate, span: searchSpan)
    }

    func expandedSearchRegion() -> MKCoordinateRegion {
        let multiplier: CLLocationDegrees = 3.25
        let latitudeDelta = min(4.5, max(searchSpan.latitudeDelta * multiplier, 0.5))
        let longitudeDelta = min(4.5, max(searchSpan.longitudeDelta * multiplier, 0.5))
        let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        return MKCoordinateRegion(center: anchorCoordinate, span: span)
    }
}

@MainActor
final class ManualPlaceResolver {
    static let shared = ManualPlaceResolver()

    private let definitions: [ManualPlaceDefinition]

    @MainActor
    private static let defaultDefinitions: [ManualPlaceDefinition] = [
        ManualPlaceDefinition(
            id: UUID(uuidString: "628C5396-CA36-4E47-B72B-6363F9DF1F3B")!,
            name: "BK Jani",
            anchorCoordinate: CLLocationCoordinate2D(latitude: 40.7020781, longitude: -73.9243236),
            halalStatus: .only,
            rating: 4.5,
            ratingCount: 250,
            confidence: 0.9,
            fallbackAddress: "276 Knickerbocker Ave, Brooklyn, NY 11237"
        )
    ]

    private struct CacheEntry {
        let place: Place?
        let timestamp: Date
    }

    private var cache: [UUID: CacheEntry] = [:]
    private let positiveCacheDuration: TimeInterval = 60 * 60 * 12
    private let negativeCacheDuration: TimeInterval = 60 * 10

    private init(definitions: [ManualPlaceDefinition]? = nil) {
        if let definitions {
            self.definitions = definitions
        } else {
            let plistExtras = Self.loadPlistDefinitions()
            self.definitions = Self.defaultDefinitions + plistExtras
        }
    }

    private static func loadPlistDefinitions() -> [ManualPlaceDefinition] {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MANUAL_PLACES") as? [[String: Any]], !raw.isEmpty else {
            return []
        }

        var defs: [ManualPlaceDefinition] = []
        for entry in raw {
            guard let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            guard let lat = entry["lat"] as? Double, let lon = entry["lon"] as? Double else { continue }

            let idString = (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = UUID(uuidString: idString ?? "") ?? UUID()
            let address = (entry["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let statusString = (entry["halal_status"] as? String)?.lowercased() ?? "yes"
            let halalStatus = Place.HalalStatus(rawValue: statusString) ?? .yes
            let rating = entry["rating"] as? Double
            let ratingCount = entry["rating_count"] as? Int
            let confidence = entry["confidence"] as? Double
            let searchQuery = (entry["search_query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let spanLat = (entry["search_span_lat"] as? Double) ?? 0.18
            let spanLon = (entry["search_span_lon"] as? Double) ?? 0.18
            let allowsBroad = (entry["allows_broad_search"] as? Bool) ?? true

            let def = ManualPlaceDefinition(
                id: id,
                name: name,
                anchorCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                halalStatus: halalStatus,
                rating: rating,
                ratingCount: ratingCount,
                confidence: confidence,
                fallbackAddress: address,
                searchQuery: searchQuery,
                searchSpan: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon),
                allowsBroadSearch: allowsBroad
            )
            defs.append(def)
        }
        return defs
    }

    func manualPlaces(in region: MKCoordinateRegion, excluding existingPlaces: [Place]) async -> [Place] {
        let existingKeys = Set(existingPlaces.map { PlaceOverrides.normalizedName(for: $0.name) })
        var resolved: [Place] = []

        for definition in definitions {
            let anchorInsideRegion = region.contains(definition.anchorCoordinate)
            let cachedCoordinateInsideRegion = cache[definition.id]?.place.map { region.contains($0.coordinate) } ?? false
            guard anchorInsideRegion || cachedCoordinateInsideRegion else { continue }
            guard let place = await resolve(definition, existingKeys: existingKeys) else { continue }
            let key = PlaceOverrides.normalizedName(for: place.name)
            guard !existingKeys.contains(key) else { continue }
            resolved.append(place)
        }

        return resolved
    }

    func searchMatches(for query: String, excluding existingPlaces: [Place]) async -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let existingKeys = Set(existingPlaces.map { PlaceOverrides.normalizedName(for: $0.name) })
        var matches: [Place] = []

        for definition in definitions where definition.matches(query: trimmed) {
            guard let place = await resolve(definition, existingKeys: existingKeys) else { continue }
            let key = PlaceOverrides.normalizedName(for: place.name)
            guard !existingKeys.contains(key) else { continue }
            matches.append(place)
        }

        return PlaceOverrides.sorted(matches)
    }

    private func resolve(_ definition: ManualPlaceDefinition, existingKeys: Set<String>) async -> Place? {
        if let cached = cache[definition.id] {
            let duration = cached.place == nil ? negativeCacheDuration : positiveCacheDuration
            if Date().timeIntervalSince(cached.timestamp) < duration {
                guard let place = cached.place else { return nil }
                let key = PlaceOverrides.normalizedName(for: place.name)
                guard !existingKeys.contains(key) else { return nil }
                return place
            }
        }

        guard let fetched = await fetchPlace(for: definition) else {
            cache[definition.id] = CacheEntry(place: nil, timestamp: Date())
            return nil
        }

        cache[definition.id] = CacheEntry(place: fetched, timestamp: Date())
        let key = PlaceOverrides.normalizedName(for: fetched.name)
        guard !existingKeys.contains(key) else { return nil }
        return fetched
    }

    private func fetchPlace(for definition: ManualPlaceDefinition) async -> Place? {
        guard let mapItem = await searchMapItem(for: definition) else { return nil }

        // Opportunistically persist the outlier into Supabase via the Apple upsert RPC
        // so future sessions/devices receive it from the backend.
        if let payload = ApplePlaceUpsertPayload(mapItem: mapItem, halalStatus: definition.halalStatus, confidence: definition.confidence) {
            Task.detached(priority: .utility) {
                do { _ = try await PlaceAPI.upsertApplePlace(payload) } catch { /* best-effort */ }
            }
        }

        return makePlace(from: mapItem, definition: definition)
    }

    private func searchMapItem(for definition: ManualPlaceDefinition) async -> MKMapItem? {
        let normalizedTarget = PlaceOverrides.normalizedName(for: definition.name)
        var regions: [MKCoordinateRegion?] = [definition.searchRegion()]
        if definition.allowsBroadSearch {
            regions.append(definition.expandedSearchRegion())
            regions.append(nil)
        }

        for region in regions {
            let items = await performSearch(query: definition.searchQuery, region: region)
            if let match = bestMatch(from: items, normalizedTarget: normalizedTarget) {
                return match
            }
        }

        return nil
    }

    private func performSearch(query: String, region: MKCoordinateRegion?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest]
        if let region {
            request.region = region
        }
        if #available(iOS 13.0, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems
        } catch {
            return []
        }
    }

    private func bestMatch(from items: [MKMapItem], normalizedTarget: String) -> MKMapItem? {
        guard !items.isEmpty else { return nil }
        let viableItems = items.filter { !isLikelyClosed($0) }
        let candidates = viableItems.isEmpty ? items : viableItems

        if let exact = candidates.first(where: { mapItemNameMatches($0, normalizedTarget: normalizedTarget) }) {
            return exact
        }

        return candidates.first
    }

    private func mapItemNameMatches(_ item: MKMapItem, normalizedTarget: String) -> Bool {
        guard let name = item.name else { return false }
        return PlaceOverrides.normalizedName(for: name) == normalizedTarget
    }

    private func isLikelyClosed(_ item: MKMapItem) -> Bool {
        guard let name = item.name?.lowercased() else { return false }
        if name.contains("permanently closed") { return true }
        if name.contains("closed permanently") { return true }
        return false
    }

    private func makePlace(from mapItem: MKMapItem, definition: ManualPlaceDefinition) -> Place {
        let coordinate = mapItem.halalCoordinate
        let address = mapItem.halalShortAddress ?? definition.fallbackAddress
        return Place(
            id: definition.id,
            name: mapItem.name ?? definition.name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: .restaurant,
            address: address,
            halalStatus: definition.halalStatus,
            rating: definition.rating,
            ratingCount: definition.ratingCount,
            confidence: definition.confidence,
            source: "Apple Maps",
            applePlaceID: mapItem.identifier?.rawValue
        )
    }
}

private extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = span.latitudeDelta / 2.0
        let halfLon = span.longitudeDelta / 2.0
        guard halfLat > 0, halfLon > 0 else { return false }

        let minLat = center.latitude - halfLat
        let maxLat = center.latitude + halfLat
        let minLon = center.longitude - halfLon
        let maxLon = center.longitude + halfLon

        return coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon
    }
}
