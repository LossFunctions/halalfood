import Foundation

struct CommunityTopRatedRecord: Decodable {
    let region: String
    let regionRank: Int
    let id: UUID
    let name: String
    let category: String
    let lat: Double
    let lon: Double
    let address: String?
    let displayLocation: String?
    let halalStatus: String?
    let rating: Double?
    let ratingCount: Int?
    let confidence: Double?
    let source: String?
    let applePlaceID: String?
    let note: String?
    let sourceRaw: PlaceDTO.SourceRaw?

    enum CodingKeys: String, CodingKey {
        case region
        case regionRank = "region_rank"
        case id
        case name
        case category
        case lat
        case lon
        case address
        case displayLocation = "display_location"
        case halalStatus = "halal_status"
        case rating
        case ratingCount = "rating_count"
        case confidence
        case source
        case applePlaceID = "apple_place_id"
        case note
        case sourceRaw = "source_raw"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decode(String.self, forKey: .region)
        regionRank = try container.decode(Int.self, forKey: .regionRank)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        displayLocation = try container.decodeIfPresent(String.self, forKey: .displayLocation)
        halalStatus = try container.decodeIfPresent(String.self, forKey: .halalStatus)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        ratingCount = try container.decodeIfPresent(Int.self, forKey: .ratingCount)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        applePlaceID = try container.decodeIfPresent(String.self, forKey: .applePlaceID)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        sourceRaw = try container.decodeIfPresent(PlaceDTO.SourceRaw.self, forKey: .sourceRaw)
    }

    func toPlaceDTO() -> PlaceDTO {
        PlaceDTO(
            id: id,
            name: name,
            category: category,
            lat: lat,
            lon: lon,
            address: address,
            display_location: displayLocation,
            halal_status: halalStatus,
            rating: rating,
            rating_count: ratingCount,
            confidence: confidence,
            source: source,
            apple_place_id: applePlaceID,
            note: note,
            source_raw: sourceRaw
        )
    }
}

