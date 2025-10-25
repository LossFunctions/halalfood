import Foundation
import MapKit
import CoreLocation

extension CLLocationCoordinate2D: @unchecked Sendable {}

enum PlaceCategory: String, Identifiable, Codable {
    case restaurant
    case other

    var id: String { rawValue }
}

struct Place: Identifiable, Hashable, Sendable {
    enum HalalStatus: String, Codable {
        case unknown
        case yes
        case only
        case no

        init(rawValue: String?) {
            guard let raw = rawValue?.lowercased(), let value = HalalStatus(rawValue: raw) else {
                self = .unknown
                return
            }
            self = value
        }

        var label: String {
            switch self {
            case .unknown: "Verification pending"
            case .yes: "Halal options"
            case .only: "Fully halal"
            case .no: "Not halal"
            }
        }
    }

    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let category: PlaceCategory
    let rawCategory: String
    let address: String?
    let halalStatus: HalalStatus
    let rating: Double?
    let ratingCount: Int?
    let confidence: Double?
    let source: String?
    let applePlaceID: String?
    let note: String?
    let displayLocation: String?

    init?(dto: PlaceDTO) {
        id = dto.id
        name = dto.name
        coordinate = CLLocationCoordinate2D(latitude: dto.lat, longitude: dto.lon)
        rawCategory = dto.category.lowercased()

        if rawCategory == "mosque" {
            return nil
        }

        category = PlaceCategory(rawValue: rawCategory) ?? .other
        address = dto.address
        halalStatus = HalalStatus(rawValue: dto.halal_status)
        rating = dto.rating
        ratingCount = dto.rating_count
        confidence = dto.confidence
        source = dto.source
        applePlaceID = dto.apple_place_id
        note = dto.note
        displayLocation = dto.source_raw?.display_location
    }
}

// RegionGate integration: provide coordinates to the geofilter
extension Place: Geolocated {
    var latitude: Double { coordinate.latitude }
    var longitude: Double { coordinate.longitude }
    var state: String? { nil }
    var country: String? { nil }
}


extension Place {
    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Place {
    init(id: UUID = UUID(),
         name: String,
         latitude: Double,
         longitude: Double,
         category: PlaceCategory = .restaurant,
         address: String? = nil,
         halalStatus: HalalStatus = .unknown,
         rating: Double? = nil,
         ratingCount: Int? = nil,
         confidence: Double? = nil,
         source: String? = "manual",
         applePlaceID: String? = nil,
         note: String? = nil,
         displayLocation: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.category = category
        self.rawCategory = category.rawValue
        self.address = address
        self.halalStatus = halalStatus
        self.rating = rating
        self.ratingCount = ratingCount
        self.confidence = confidence
        self.source = source
        self.applePlaceID = applePlaceID
        self.note = note
        self.displayLocation = displayLocation
    }

    init(id: UUID,
         name: String,
         coordinate: CLLocationCoordinate2D,
         category: PlaceCategory,
         rawCategory: String,
         address: String?,
         halalStatus: HalalStatus,
         rating: Double?,
         ratingCount: Int?,
         confidence: Double?,
         source: String?,
         applePlaceID: String?,
         note: String?,
         displayLocation: String?) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.category = category
        self.rawCategory = rawCategory
        self.address = address
        self.halalStatus = halalStatus
        self.rating = rating
        self.ratingCount = ratingCount
        self.confidence = confidence
        self.source = source
        self.applePlaceID = applePlaceID
        self.note = note
        self.displayLocation = displayLocation
    }
}

extension Place: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case category
        case rawCategory
        case address
        case halalStatus
        case rating
        case ratingCount
        case confidence
        case source
        case applePlaceID
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let category = try container.decode(PlaceCategory.self, forKey: .category)
        let rawCategory = try container.decodeIfPresent(String.self, forKey: .rawCategory) ?? category.rawValue
        let address = try container.decodeIfPresent(String.self, forKey: .address)
        let halalStatus = try container.decode(Place.HalalStatus.self, forKey: .halalStatus)
        let rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        let ratingCount = try container.decodeIfPresent(Int.self, forKey: .ratingCount)
        let confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        let applePlaceID = try container.decodeIfPresent(String.self, forKey: .applePlaceID)
        let note = try container.decodeIfPresent(String.self, forKey: .note)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        self.init(
            id: id,
            name: name,
            coordinate: coordinate,
            category: category,
            rawCategory: rawCategory,
            address: address,
            halalStatus: halalStatus,
            rating: rating,
            ratingCount: ratingCount,
            confidence: confidence,
            source: source,
            applePlaceID: applePlaceID,
            note: note,
            displayLocation: nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(category, forKey: .category)
        try container.encode(rawCategory, forKey: .rawCategory)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encode(halalStatus, forKey: .halalStatus)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(ratingCount, forKey: .ratingCount)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(applePlaceID, forKey: .applePlaceID)
        try container.encodeIfPresent(note, forKey: .note)
        // displayLocation is derived from server source_raw and not encoded here
    }
}
enum PlaceOverrides {
    private static let permanentlyClosedNames: Set<String> = {
        let names = [
            "Sofra Mediterranean Grill",
            "Sofra Mediterranean Grill (Permanently Closed)",
            "Habibi Rooftop the Restaurant",
            "Habibi Rooftop Restaurant",
            "Blue Hour"
        ]
        return Set(names.map { normalizedName(for: $0) })
    }()

    static func apply(overridesTo places: [Place], in _: MKCoordinateRegion) -> [Place] {
        let filtered = places.filter { !isMarkedClosed(name: $0.name) }
        let sanitized = removingOutdatedDuplicates(from: filtered)
        return sorted(sanitized)
    }

    nonisolated static func normalizedName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(scalars.map(Character.init)).lowercased()
    }

    static func isMarkedClosed(name: String) -> Bool {
        if permanentlyClosedNames.contains(normalizedName(for: name)) { return true }
        let lowercased = name.lowercased()
        if lowercased.contains("permanently closed") { return true }
        if lowercased.contains("closed permanently") { return true }
        return false
    }

    static func deduplicate(_ places: [Place]) -> [Place] {
        sanitize(places, dropOutdatedOSM: false)
    }

    private static func removingOutdatedDuplicates(from places: [Place]) -> [Place] {
        sanitize(places, dropOutdatedOSM: true)
    }

    private static func sanitize(_ places: [Place], dropOutdatedOSM: Bool) -> [Place] {
        guard places.count > 1 else { return places }

        let prioritized = places.sorted(by: duplicatePriorityPredicate(_:_:))
        let highPriority = dropOutdatedOSM ? prioritized.filter { sourcePriority(for: $0.source) > sourcePriority(for: "osm") } : []
        let highPriorityIndex = dropOutdatedOSM ? buildCoordinateIndex(for: highPriority) : [:]
        let highPriorityTokenCache = dropOutdatedOSM ? Dictionary(uniqueKeysWithValues: highPriority.map { ($0.id, significantTokens(for: $0.name)) }) : [:]
        let highPriorityLocationCache = dropOutdatedOSM ? Dictionary(uniqueKeysWithValues: highPriority.compactMap { place -> (UUID, CLLocation)? in
            guard let location = location(for: place.coordinate) else { return nil }
            return (place.id, location)
        }) : [:]

        var result: [Place] = []
        var addressIndex: [String: [Place]] = [:]
        var coordinateIndex: [CoordinateBucket: [Place]] = [:]
        var acceptedLocationCache: [UUID: CLLocation] = [:]

        for place in prioritized {
            let placeLocation = location(for: place.coordinate)

            if dropOutdatedOSM {
                let placeTokens = significantTokens(for: place.name)
                if shouldDrop(osmPlace: place,
                              placeTokens: placeTokens,
                              placeLocation: placeLocation,
                              using: highPriorityIndex,
                              tokenCache: highPriorityTokenCache,
                              locationCache: highPriorityLocationCache) {
                    continue
                }
            }

            if isDuplicate(place,
                           placeLocation: placeLocation,
                           addressIndex: addressIndex,
                           coordinateIndex: coordinateIndex,
                           locationCache: acceptedLocationCache) {
                continue
            }

            result.append(place)
            if let location = placeLocation { acceptedLocationCache[place.id] = location }
            if let normalizedAddress = normalizedAddress(place.address) {
                addressIndex[normalizedAddress, default: []].append(place)
            }
            if let bucket = coordinateBucket(for: place.coordinate) {
                coordinateIndex[bucket, default: []].append(place)
            }
        }

        return result
    }

    private static func shouldDrop(osmPlace place: Place,
                                   placeTokens: Set<String>,
                                   placeLocation: CLLocation?,
                                   using index: [CoordinateBucket: [Place]],
                                   tokenCache: [UUID: Set<String>],
                                   locationCache: [UUID: CLLocation]) -> Bool {
        guard normalizedSource(place.source) == "osm",
              !index.isEmpty,
              let placeLocation,
              !placeTokens.isEmpty else { return false }

        for bucket in neighborBuckets(for: place.coordinate) {
            guard let candidates = index[bucket] else { continue }
            for candidate in candidates {
                let candidateTokens = tokenCache[candidate.id] ?? significantTokens(for: candidate.name)
                guard !candidateTokens.isEmpty else { continue }
                guard placeTokens.isDisjoint(with: candidateTokens) else { continue }
                let candidateLocation = locationCache[candidate.id] ?? location(for: candidate.coordinate)
                guard let candidateLocation else { continue }
                let distance = placeLocation.distance(from: candidateLocation)
                if distance <= osmConflictDistanceThreshold {
                    return true
                }
            }
        }

        return false
    }

    private static func significantTokens(for name: String) -> Set<String> {
        let lowercased = name.lowercased()
        var buffer: [Character] = []
        var tokens: [String] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            let token = String(buffer)
            if token.count >= 2, !genericNameTokens.contains(token) {
                tokens.append(token)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for scalar in lowercased.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                buffer.append(Character(scalar))
            } else {
                flush()
            }
        }
        flush()

        return Set(tokens)
    }

    static func isDuplicate(_ lhs: Place, of rhs: Place) -> Bool {
        guard lhs.id != rhs.id else { return true }

        if addressesMatch(lhs.address, rhs.address) && namesCompatible(lhs.name, rhs.name) {
            return true
        }

        let lhsLocation = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
        let rhsLocation = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
        let distance = lhsLocation.distance(from: rhsLocation)

        if distance <= duplicateDistanceThreshold && namesCompatible(lhs.name, rhs.name) {
            return true
        }

        return false
    }

    private static func isDuplicate(_ place: Place,
                                    placeLocation: CLLocation?,
                                    addressIndex: [String: [Place]],
                                    coordinateIndex: [CoordinateBucket: [Place]],
                                    locationCache: [UUID: CLLocation]) -> Bool {
        if let normalizedAddress = normalizedAddress(place.address),
           let candidates = addressIndex[normalizedAddress] {
            for candidate in candidates {
                if namesCompatible(place.name, candidate.name) {
                    return true
                }
            }
        }

        guard let placeLocation else { return false }

        for bucket in neighborBuckets(for: place.coordinate) {
            guard let candidates = coordinateIndex[bucket] else { continue }
            for candidate in candidates {
                let candidateLocation = locationCache[candidate.id] ?? location(for: candidate.coordinate)
                guard let candidateLocation else { continue }
                let distance = placeLocation.distance(from: candidateLocation)
                guard distance <= duplicateDistanceThreshold else { continue }
                if namesCompatible(place.name, candidate.name) {
                    return true
                }
            }
        }

        return false
    }

    private static func namesCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedL = normalizedName(for: lhs)
        let normalizedR = normalizedName(for: rhs)

        if normalizedL == normalizedR { return true }
        if normalizedL.isEmpty || normalizedR.isEmpty { return false }
        if normalizedL.contains(normalizedR) || normalizedR.contains(normalizedL) {
            return true
        }

        let lhsTokens = significantTokens(for: lhs)
        let rhsTokens = significantTokens(for: rhs)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }

        let overlap = lhsTokens.intersection(rhsTokens)
        if overlap.isEmpty { return false }

        if overlap == lhsTokens || overlap == rhsTokens { return true }

        let minimumRequired = min(2, min(lhsTokens.count, rhsTokens.count))
        return overlap.count >= minimumRequired
    }

    private static func addressesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let normalizedL = normalizedAddress(lhs),
              let normalizedR = normalizedAddress(rhs) else { return false }
        return normalizedL == normalizedR
    }

    private static func normalizedAddress(_ address: String?) -> String? {
        guard let raw = address?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = normalizedName(for: raw)
        return normalized.isEmpty ? nil : normalized
    }

    private static func duplicatePriorityPredicate(_ lhs: Place, _ rhs: Place) -> Bool {
        let lhsScore = duplicatePriorityScore(for: lhs)
        let rhsScore = duplicatePriorityScore(for: rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return placeSortPredicate(lhs, rhs)
    }

    private static func duplicatePriorityScore(for place: Place) -> Double {
        let priority = Double(sourcePriority(for: place.source))
        let confidence = (place.confidence ?? 0) * 100
        let rating = (place.rating ?? 0) * 10
        let ratingCountBonus = sqrt(Double(place.ratingCount ?? 0))
        let halalBonus: Double
        switch place.halalStatus {
        case .only:
            halalBonus = 18_000
        case .yes:
            halalBonus = 15_000
        case .unknown:
            halalBonus = 0
        case .no:
            halalBonus = -20_000
        }
        return priority * 10_000 + halalBonus + confidence + rating + ratingCountBonus
    }

    private static func sourcePriority(for source: String?) -> Int {
        switch normalizedSource(source) {
        case "yelp": return 4
        case "apple": return 3
        case "manual": return 2
        case "osm": return 1
        default: return 1
        }
    }

    private static func normalizedSource(_ source: String?) -> String {
        guard let raw = source?.lowercased() else { return "unknown" }
        if raw.contains("manual") { return "manual" }
        if raw.contains("yelp") { return "yelp" }
        if raw.contains("apple") { return "apple" }
        if raw.contains("osm") { return "osm" }
        return raw
    }

    private static func coordinateBucket(for coordinate: CLLocationCoordinate2D) -> CoordinateBucket? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }
        let latIndex = Int((coordinate.latitude / coordinateBucketSize).rounded())
        let lonIndex = Int((coordinate.longitude / coordinateBucketSize).rounded())
        return CoordinateBucket(latIndex: latIndex, lonIndex: lonIndex)
    }

    private static func neighborBuckets(for coordinate: CLLocationCoordinate2D) -> [CoordinateBucket] {
        guard let base = coordinateBucket(for: coordinate) else { return [] }
        var buckets: [CoordinateBucket] = []
        buckets.reserveCapacity(9)
        for dLat in -1...1 {
            for dLon in -1...1 {
                buckets.append(CoordinateBucket(latIndex: base.latIndex + dLat, lonIndex: base.lonIndex + dLon))
            }
        }
        return buckets
    }

    private static func buildCoordinateIndex(for places: [Place]) -> [CoordinateBucket: [Place]] {
        var index: [CoordinateBucket: [Place]] = [:]
        for place in places {
            guard let bucket = coordinateBucket(for: place.coordinate) else { continue }
            index[bucket, default: []].append(place)
        }
        return index
    }

    private static func location(for coordinate: CLLocationCoordinate2D) -> CLLocation? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private static let duplicateDistanceThreshold: CLLocationDistance = 55

    private static let osmConflictDistanceThreshold: CLLocationDistance = 65

    private static let coordinateBucketSize: CLLocationDegrees = 0.0005

    private static let genericNameTokens: Set<String> = {
        let words = [
            "the", "and", "ny", "nyc", "new", "city", "cafe", "food",
            "market", "mart", "shop", "deli", "restaurant", "grill", "kitchen",
            "house", "bar", "bbq", "express", "taste", "place", "spot", "cuisine",
            "kabab", "kebab", "shawarma", "gyro", "chicken", "pizza", "burger",
            "garden", "corner", "islamic", "masjid"
        ]
        return Set(words)
    }()

    private struct CoordinateBucket: Hashable {
        let latIndex: Int
        let lonIndex: Int
    }

    static func sorted(_ places: [Place]) -> [Place] {
        places.sorted(by: placeSortPredicate(_:_:))
    }

    nonisolated private static func placeSortPredicate(_ lhs: Place, _ rhs: Place) -> Bool {
        switch (lhs.rating, rhs.rating) {
        case let (l?, r?) where l != r:
            return l > r
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }

        switch (lhs.confidence, rhs.confidence) {
        case let (l?, r?) where l != r:
            return l > r
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }

        let lhsName = lhs.name.lowercased()
        let rhsName = rhs.name.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
