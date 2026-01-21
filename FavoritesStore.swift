import Combine
import CoreLocation
import Foundation

struct FavoritePlaceSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var categoryRaw: String
    var halalStatusRaw: String
    var rating: Double?
    var ratingCount: Int?
    var source: String?
    var sourceID: String?
    var externalID: String?
    var applePlaceID: String?
    var savedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var category: PlaceCategory {
        PlaceCategory(rawValue: categoryRaw) ?? .restaurant
    }

    var halalStatus: Place.HalalStatus {
        Place.HalalStatus(rawValue: halalStatusRaw)
    }

    func updating(from place: Place,
                  name: String,
                  address: String?,
                  rating: Double?,
                  ratingCount: Int?,
                  source: String?,
                  sourceID: String?,
                  externalID: String?,
                  applePlaceID: String?) -> FavoritePlaceSnapshot {
        FavoritePlaceSnapshot(
            id: id,
            name: name,
            address: address,
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude,
            categoryRaw: place.category.rawValue,
            halalStatusRaw: place.halalStatus.rawValue,
            rating: rating,
            ratingCount: ratingCount,
            source: source,
            sourceID: sourceID,
            externalID: externalID,
            applePlaceID: applePlaceID ?? place.applePlaceID,
            savedAt: savedAt
        )
    }
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoritePlaceSnapshot] = [] {
        didSet { favoriteIDs = Set(favorites.map(\.id)) }
    }

    private let storageKey = "favorite_place_snapshots"
    private let defaults: UserDefaults
    private var favoriteIDs: Set<UUID> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isFavorite(_ place: Place) -> Bool {
        favoriteIDs.contains(place.id)
    }

    func contains(id: UUID) -> Bool {
        favoriteIDs.contains(id)
    }

    func toggleFavorite(for place: Place,
                        name: String,
                        address: String?,
                        rating: Double?,
                        ratingCount: Int?,
                        source: String?,
                        sourceID: String?,
                        externalID: String?,
                        applePlaceID: String?) {
        if favoriteIDs.contains(place.id) {
            removeFavorite(withId: place.id)
        } else {
            addFavorite(from: place,
                        name: name,
                        address: address,
                        rating: rating,
                        ratingCount: ratingCount,
                        source: source,
                        sourceID: sourceID,
                        externalID: externalID,
                        applePlaceID: applePlaceID)
        }
    }

    func updateFavoriteIfNeeded(for place: Place,
                                name: String,
                                address: String?,
                                rating: Double?,
                                ratingCount: Int?,
                                source: String?,
                                sourceID: String?,
                                externalID: String?,
                                applePlaceID: String?) {
        guard let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index] = favorites[index].updating(from: place,
                                                     name: name,
                                                     address: address,
                                                     rating: rating,
                                                     ratingCount: ratingCount,
                                                     source: source,
                                                     sourceID: sourceID,
                                                     externalID: externalID,
                                                     applePlaceID: applePlaceID)
        persist()
    }

    func removeFavorite(withId id: UUID) {
        guard favoriteIDs.contains(id) else { return }
        favorites.removeAll { $0.id == id }
        persist()
    }

    private func addFavorite(from place: Place,
                             name: String,
                             address: String?,
                             rating: Double?,
                             ratingCount: Int?,
                             source: String?,
                             sourceID: String?,
                             externalID: String?,
                             applePlaceID: String?) {
        let snapshot = FavoritePlaceSnapshot(
            id: place.id,
            name: name,
            address: address,
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude,
            categoryRaw: place.category.rawValue,
            halalStatusRaw: place.halalStatus.rawValue,
            rating: rating,
            ratingCount: ratingCount,
            source: source,
            sourceID: sourceID,
            externalID: externalID,
            applePlaceID: applePlaceID ?? place.applePlaceID,
            savedAt: Date()
        )

        favorites.append(snapshot)
        favorites.sort(by: recencySort)
        persist()
    }

    private func recencySort(_ lhs: FavoritePlaceSnapshot, _ rhs: FavoritePlaceSnapshot) -> Bool {
        if lhs.savedAt == rhs.savedAt {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.savedAt > rhs.savedAt
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            favorites = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([FavoritePlaceSnapshot].self, from: data)
            let sanitized = decoded.map { $0.removingYelpRatings() }
            favorites = sanitized.sorted(by: recencySort)
            if decoded != sanitized {
                persist()
            }
        } catch {
#if DEBUG
            print("[FavoritesStore] Failed to decode favorites:", error)
#endif
            favorites = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(favorites)
            defaults.set(data, forKey: storageKey)
        } catch {
#if DEBUG
            print("[FavoritesStore] Failed to persist favorites:", error)
#endif
        }
    }
}

extension FavoritePlaceSnapshot {
    func toPlace() -> Place {
        Place(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            address: address,
            halalStatus: Place.HalalStatus(rawValue: halalStatusRaw),
            rating: rating,
            ratingCount: ratingCount,
            source: source,
            sourceID: sourceID,
            externalID: externalID,
            applePlaceID: applePlaceID
        )
    }
}

extension FavoritePlaceSnapshot {
    var isYelpBacked: Bool {
        if let source, source.lowercased().contains("yelp") { return true }
        if let externalID, externalID.lowercased().hasPrefix("yelp:") { return true }
        return false
    }

    func removingYelpRatings() -> FavoritePlaceSnapshot {
        guard isYelpBacked else { return self }
        var copy = self
        copy.rating = nil
        copy.ratingCount = nil
        return copy
    }

    var displayRating: Double? {
        isYelpBacked ? nil : rating
    }

    var displayRatingCount: Int? {
        isYelpBacked ? nil : ratingCount
    }
}
