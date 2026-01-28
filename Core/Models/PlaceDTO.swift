import Foundation

nonisolated struct PlaceDTO: Decodable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let category_label: String?
    let lat: Double
    let lon: Double
    let address: String?
    let display_location: String?
    let halal_status: String?
    let rating: Double?
    let rating_count: Int?
    let serves_alcohol: Bool?
    let source: String?
    let source_id: String?
    let external_id: String?
    let google_place_id: String?
    let google_match_status: String?
    let google_maps_url: String?
    let google_business_status: String?
    let apple_place_id: String?
    let note: String?
    let cc_certifier_org: String?
    let source_raw: SourceRaw?

    nonisolated struct SourceRaw: Decodable {
        let display_location: String?
        let categories: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case category_label
        case lat
        case lon
        case address
        case display_location
        case halal_status
        case rating
        case rating_count
        case serves_alcohol
        case source
        case source_id
        case external_id
        case google_place_id
        case google_match_status
        case google_maps_url
        case google_business_status
        case apple_place_id
        case note
        case cc_certifier_org
        case source_raw
    }
}
