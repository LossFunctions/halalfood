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

    static func apply(overridesTo places: [Place], in _: MKCoordinateRegion) -> [Place] {
        let filtered = places.filter { !isMarkedClosed(name: $0.name) }
        return sorted(filtered)
    }

    nonisolated static func normalizedName(for name: String) -> String {
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
