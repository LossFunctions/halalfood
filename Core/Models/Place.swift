import Foundation
import MapKit

enum PlaceCategory: String, Identifiable {
    case restaurant
    case other

    var id: String { rawValue }
}

struct Place: Identifiable, Hashable {
    enum HalalStatus: String {
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
    }
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
         applePlaceID: String? = nil) {
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
    }
}

enum PlaceOverrides {
    private static let permanentlyClosedNames: Set<String> = {
        let names = [
            "Sofra Mediterranean Grill",
            "Sofra Mediterranean Grill (Permanently Closed)"
        ]
        return Set(names.map { normalizedName(for: $0) })
    }()

    private static let manualEntries: [Place] = [
        Place(
            name: "BK Jani",
            latitude: 40.7020781,
            longitude: -73.9243236,
            address: "276 Knickerbocker Ave, Brooklyn, NY 11237",
            halalStatus: .only,
            rating: 4.5,
            ratingCount: 250,
            confidence: 0.9,
            source: "manual"
        )
    ]

    static func apply(overridesTo places: [Place], in region: MKCoordinateRegion) -> [Place] {
        var filtered = places.filter { !isMarkedClosed(name: $0.name) }

        var existingKeys = Set(filtered.map { normalizedName(for: $0.name) })

        for manualPlace in manualEntries(in: region) {
            let key = normalizedName(for: manualPlace.name)
            guard !existingKeys.contains(key) else { continue }
            filtered.append(manualPlace)
            existingKeys.insert(key)
        }

        return sorted(filtered)
    }

    static func normalizedName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(scalars.map(Character.init)).lowercased()
    }

    private static func isMarkedClosed(name: String) -> Bool {
        if permanentlyClosedNames.contains(normalizedName(for: name)) { return true }
        let lowercased = name.lowercased()
        if lowercased.contains("permanently closed") { return true }
        if lowercased.contains("closed permanently") { return true }
        return false
    }

    private static func manualEntries(in region: MKCoordinateRegion) -> [Place] {
        manualEntries.filter { regionContains(region, coordinate: $0.coordinate) }
    }

    static func searchMatches(for query: String, knownPlaces: [Place]) -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let existingKeys = Set(knownPlaces.map { normalizedName(for: $0.name) })

        let matches = manualEntries.filter { place in
            let key = normalizedName(for: place.name)
            guard !existingKeys.contains(key) else { return false }
            if place.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if place.address?.localizedCaseInsensitiveContains(trimmed) == true { return true }
            return false
        }

        return sorted(matches)
    }

    static func sorted(_ places: [Place]) -> [Place] {
        places.sorted(by: placeSortPredicate(_:_:))
    }

    private static func regionContains(_ region: MKCoordinateRegion, coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = region.span.latitudeDelta / 2.0
        let halfLon = region.span.longitudeDelta / 2.0
        guard halfLat > 0, halfLon > 0 else { return false }

        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        return coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon
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
