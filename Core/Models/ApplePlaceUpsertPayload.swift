import Foundation
import MapKit

struct ApplePlaceUpsertPayload: Encodable, Sendable {
    let applePlaceID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let halalStatus: String
    let rating: Double?
    let ratingCount: Int?
    let confidence: Double?

    init?(mapItem: MKMapItem,
          halalStatus: Place.HalalStatus = .unknown,
          confidence: Double? = 0.6) {
        let trimmedName = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else { return nil }

        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        self.applePlaceID = mapItem.halalPersistentIdentifier
        self.name = trimmedName
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = mapItem.halalShortAddress
        self.halalStatus = halalStatus.rawValue
        self.rating = nil
        self.ratingCount = nil
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case applePlaceID = "p_apple_place_id"
        case name = "p_name"
        case latitude = "p_lat"
        case longitude = "p_lon"
        case address = "p_address"
        case halalStatus = "p_halal_status"
        case rating = "p_rating"
        case ratingCount = "p_rating_count"
        case confidence = "p_confidence"
    }
}
