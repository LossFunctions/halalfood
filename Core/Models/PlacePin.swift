import Foundation
import CoreLocation

struct PlacePinDTO: Decodable {
    let id: UUID
    let lat: Double
    let lon: Double
    let halal_status: String?
    let updated_at: String?
    let address: String?
}

struct PlacePin: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let halalStatus: Place.HalalStatus
    let updatedAt: String?
    let address: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID,
        latitude: Double,
        longitude: Double,
        halalStatus: Place.HalalStatus,
        updatedAt: String? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.halalStatus = halalStatus
        self.updatedAt = updatedAt
        self.address = address
    }

    init(dto: PlacePinDTO) {
        id = dto.id
        latitude = dto.lat
        longitude = dto.lon
        halalStatus = Place.HalalStatus(rawValue: dto.halal_status)
        updatedAt = dto.updated_at
        address = dto.address
    }

    init(place: Place) {
        id = place.id
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        halalStatus = place.halalStatus
        updatedAt = nil
        address = place.address
    }
}

extension PlacePin: Geolocated {
    var state: String? {
        guard let address, !address.isEmpty else { return nil }
        return RegionGate.deriveUSStateCode(fromAddress: address)
    }
    var country: String? { nil }
}
