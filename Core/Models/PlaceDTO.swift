import Foundation

struct PlaceDTO: Decodable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let lat: Double
    let lon: Double
    let address: String?
    let display_location: String?
    let halal_status: String?
    let rating: Double?
    let rating_count: Int?
    let confidence: Double?
    let source: String?
    let apple_place_id: String?
    let note: String?
    let source_raw: SourceRaw?

    struct SourceRaw: Decodable {
        let display_location: String?
        let categories: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case lat
        case lon
        case address
        case display_location
        case halal_status
        case rating
        case rating_count
        case confidence
        case source
        case apple_place_id
        case note
        case source_raw
    }
}
