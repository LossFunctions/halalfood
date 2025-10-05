import Foundation

struct PlacePhoto: Decodable, Identifiable, Hashable {
    let id: UUID
    let placeId: UUID
    let src: String
    let externalId: String?
    let imageUrl: String
    let width: Int?
    let height: Int?
    let priority: Int?
    let attribution: String?
}
