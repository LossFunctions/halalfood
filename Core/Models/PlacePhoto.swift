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

extension PlacePhoto {
    init(placeID: UUID, position: Int, url: String, attribution: String?) {
        self.id = UUID()
        self.placeId = placeID
        self.src = "yelp"
        self.externalId = "yelp:\(position)"
        self.imageUrl = url
        self.width = nil
        self.height = nil
        self.priority = position
        self.attribution = attribution
    }

    init(placeID: UUID,
         position: Int,
         url: String,
         attribution: String?,
         source: String,
         externalId: String? = nil,
         width: Int? = nil,
         height: Int? = nil) {
        self.id = UUID()
        self.placeId = placeID
        self.src = source
        self.externalId = externalId
        self.imageUrl = url
        self.width = width
        self.height = height
        self.priority = position
        self.attribution = attribution
    }
}
