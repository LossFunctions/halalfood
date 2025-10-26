import Combine
import Foundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum MapFilter: CaseIterable, Identifiable {
    case all
    case fullyHalal
    case partialHalal

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .fullyHalal: return "Fully Halal"
        case .partialHalal: return "Partial Halal"
        }
    }
}

private enum FavoritesSortOption: String, CaseIterable, Identifiable {
    case recentlySaved
    case alphabetical
    case rating

    var id: Self { self }

    var title: String {
        switch self {
        case .recentlySaved: return "Recent"
        case .alphabetical: return "A–Z"
        case .rating: return "Rating"
        }
    }
}

private enum TopRatedSortOption: String, CaseIterable, Identifiable {
    case yelp
    case community

    var id: Self { self }

    var title: String {
        switch self {
        case .yelp: return "Yelp Ratings"
        case .community: return "Community Ratings"
        }
    }
}

private enum TopRatedRegion: String, CaseIterable, Identifiable {
    case all
    case manhattan
    case brooklyn
    case queens
    case bronx
    case statenIsland
    case longIsland

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All Locations"
        case .manhattan: return "Manhattan"
        case .brooklyn: return "Brooklyn"
        case .queens: return "Queens"
        case .bronx: return "Bronx"
        case .statenIsland: return "Staten Island"
        case .longIsland: return "Long Island"
        }
    }
}

private enum CommunityTopRatedConfig {
    static let regions: [TopRatedRegion] = [.manhattan, .brooklyn, .queens, .bronx, .statenIsland, .longIsland]

    static let curatedNames: [TopRatedRegion: [String]] = [
        .manhattan: [
            "Top Thai",
            "Balade Your Way",
            "Adel's",
            "Au' Zatar East Village",
            "Nishaan"
        ],
        .queens: [
            "Zyara Restaurant",
            "Nur Thai",
            "Mahmoud's Corner",
            "Little Flower Cafe",
            "Darjeeling Kitchen & Cafe"
        ],
        .brooklyn: [
            "BK Jani",
            "Namkeen",
            "Monkey King",
            "Zatar",
            "Affy's"
        ],
        .bronx: [
            "Waleed's Kitchen & Hot Wings",
            "Blazin Chicken & Gyro",
            "Fry Chick",
            "Sooq NYC",
            "Halal Indian Grill"
        ],
        .longIsland: [
            "Zaoq",
            "Choopan",
            "Guac Time",
            "Halal Express Kabab House",
            "While in Kathmandu"
        ],
        .statenIsland: []
    ]

}

private struct NewSpotConfig: Identifiable {
    let id = UUID()
    let placeID: UUID
    let imageURL: URL
    let photoDescription: String?
    let displayLocation: String
    let cuisine: String
    let halalStatusOverride: Place.HalalStatus?
    let openedOn: (month: String, day: String)
    let spotlightSummary: String?
    let spotlightBody: String?
    let spotlightDetails: String?

    init(
        placeID: UUID,
        imageURL: URL,
        photoDescription: String? = nil,
        displayLocation: String,
        cuisine: String,
        halalStatusOverride: Place.HalalStatus? = nil,
        openedOn: (month: String, day: String),
        spotlightSummary: String? = nil,
        spotlightBody: String? = nil,
        spotlightDetails: String? = nil
    ) {
        self.placeID = placeID
        self.imageURL = imageURL
        self.photoDescription = photoDescription
        self.displayLocation = displayLocation
        self.cuisine = cuisine
        self.halalStatusOverride = halalStatusOverride
        self.openedOn = openedOn
        self.spotlightSummary = spotlightSummary
        self.spotlightBody = spotlightBody
        self.spotlightDetails = spotlightDetails
    }
}

private struct NewSpotEntry: Identifiable {
    var id: UUID { place.id }
    let place: Place
    let imageURL: URL
    let photoDescription: String?
    let displayLocation: String
    let cuisine: String
    let halalStatusOverride: Place.HalalStatus?
    let openedOn: (month: String, day: String)
    let spotlightSummary: String?
    let spotlightBody: String?
    let spotlightDetails: String?

    init(
        place: Place,
        imageURL: URL,
        photoDescription: String? = nil,
        displayLocation: String,
        cuisine: String,
        halalStatusOverride: Place.HalalStatus? = nil,
        openedOn: (month: String, day: String),
        spotlightSummary: String? = nil,
        spotlightBody: String? = nil,
        spotlightDetails: String? = nil
    ) {
        self.place = place
        self.imageURL = imageURL
        self.photoDescription = photoDescription
        self.displayLocation = displayLocation
        self.cuisine = cuisine
        self.halalStatusOverride = halalStatusOverride
        self.openedOn = openedOn
        self.spotlightSummary = spotlightSummary
        self.spotlightBody = spotlightBody
        self.spotlightDetails = spotlightDetails
    }
}

private enum CommunityRegionClassifier {
    static func matches(_ place: Place, region: TopRatedRegion) -> Bool {
        guard region != .all else { return true }
        return regionForPlace(place) == region
    }

    static func regionForPlace(_ place: Place) -> TopRatedRegion? {
        if let addr = place.address?.lowercased() {
            if let zip = extractZip(addr), let regionFromZip = regionFromZip(zip) {
                return regionFromZip
            }
            if addr.contains(" ny 100") || addr.contains(" new york, ny 100") || addr.contains(" new york ny 100") { return .manhattan }

            let queensKeys = [
                " queens", "sunnyside", "astoria", "long island city", " lic ",
                "jackson heights", "flushing", "jamaica, ny", "woodside", "elmhurst",
                "forest hills", "rego park", "kew gardens", "richmond hill", "ozone park",
                "bayside", "whitestone", "college point", "far rockaway", "rockaway"
            ]
            if queensKeys.contains(where: { addr.contains($0) }) { return .queens }

            if addr.contains(" brooklyn") { return .brooklyn }
            if addr.contains(" bronx") { return .bronx }
            if addr.contains(" staten island") { return .statenIsland }

            if addr.contains(" long island") && !addr.contains("long island city") { return .longIsland }
        }
        return regionForCoordinate(place.coordinate)
    }

    private static func extractZip(_ address: String) -> String? {
        let pattern = #"\b(\d{5})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(address.startIndex..<address.endIndex, in: address)
        guard let match = regex.firstMatch(in: address, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: address) else {
            return nil
        }
        return String(address[swiftRange])
    }

    private static func regionFromZip(_ zip: String) -> TopRatedRegion? {
        guard zip.count == 5 else { return nil }
        let prefix3 = String(zip.prefix(3))
        switch prefix3 {
        case "100", "101", "102": return .manhattan
        case "112": return .brooklyn
        case "111", "113", "114", "116": return .queens
        case "104": return .bronx
        case "103": return .statenIsland
        case "110", "115", "117", "118": return .longIsland
        default: return nil
        }
    }

    private static func regionForCoordinate(_ coordinate: CLLocationCoordinate2D) -> TopRatedRegion? {
        struct RegionBox { let region: TopRatedRegion; let lat: ClosedRange<Double>; let lon: ClosedRange<Double>; let centroid: CLLocationCoordinate2D }

        let boxes: [RegionBox] = [
            .init(region: .manhattan,    lat: 40.68...40.90, lon: (-74.03)...(-73.92), centroid: .init(latitude: 40.7831, longitude: -73.9712)),
            .init(region: .brooklyn,     lat: 40.56...40.74, lon: (-74.05)...(-73.83), centroid: .init(latitude: 40.6500, longitude: -73.9496)),
            .init(region: .queens,       lat: 40.54...40.81, lon: (-73.96)...(-73.70), centroid: .init(latitude: 40.7282, longitude: -73.7949)),
            .init(region: .bronx,        lat: 40.79...40.93, lon: (-73.93)...(-73.76), centroid: .init(latitude: 40.8448, longitude: -73.8648)),
            .init(region: .statenIsland, lat: 40.48...40.65, lon: (-74.27)...(-74.05), centroid: .init(latitude: 40.5795, longitude: -74.1502))
        ]

        let candidates = boxes.filter { box in
            latRangeContains(box.lat, coordinate: coordinate) && lonRangeContains(box.lon, coordinate: coordinate)
        }

        if candidates.count == 1 {
            return candidates.first?.region
        }
        if candidates.count > 1 {
            let best = candidates.min(by: { a, b in
                squaredDistance(coordinate, a.centroid) < squaredDistance(coordinate, b.centroid)
            })
            return best?.region
        }

        let inLongIslandBox = latRangeContains(40.55...41.20, coordinate: coordinate) &&
            lonRangeContains((-73.95)...(-71.75), coordinate: coordinate)
        if inLongIslandBox { return .longIsland }
        return nil
    }

    private static func squaredDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = a.latitude - b.latitude
        let dy = a.longitude - b.longitude
        return dx * dx + dy * dy
    }

    private static func latRangeContains(_ range: ClosedRange<Double>, coordinate: CLLocationCoordinate2D) -> Bool {
        range.contains(coordinate.latitude)
    }

    private static func lonRangeContains(_ range: ClosedRange<Double>, coordinate: CLLocationCoordinate2D) -> Bool {
        range.contains(coordinate.longitude)
    }
}

private struct CommunityTopRatedSnapshot: Sendable {
    let allPlaces: [Place]
    let globalPlaces: [Place]
    let searchResults: [Place]
    let yelpFallback: [Place]
}

private struct CommunityComputationResult: Sendable {
    let regionResults: [TopRatedRegion: [Place]]
}

private enum CommunityTopRatedEngine {
    static func compute(snapshot: CommunityTopRatedSnapshot) -> CommunityComputationResult {
        var regionResults: [TopRatedRegion: [Place]] = [:]
        var nameMatches: [String: [Place]] = [:]

        var pool: [Place] = snapshot.allPlaces
        if !snapshot.globalPlaces.isEmpty {
            pool.append(contentsOf: snapshot.globalPlaces)
        }
        if !snapshot.searchResults.isEmpty {
            pool.append(contentsOf: snapshot.searchResults)
        }

        let dedupedPool = PlaceOverrides.deduplicate(pool)
        let filteredPool = dedupedPool.filteredByCurrentGeoScope()

        let yelpBase = snapshot.yelpFallback
        var fallbackByRegion: [TopRatedRegion: [Place]] = [:]
        for region in CommunityTopRatedConfig.regions {
            let matches = yelpBase.filter { CommunityRegionClassifier.matches($0, region: region) }
            fallbackByRegion[region] = Array(matches.prefix(20))
        }

        for region in CommunityTopRatedConfig.regions {
            let curatedNames = CommunityTopRatedConfig.curatedNames[region] ?? []
            var curatedResults: [Place] = []

            for name in curatedNames {
                let normalized = PlaceOverrides.normalizedName(for: name)
                guard !normalized.isEmpty else { continue }

                let matches: [Place]
                if let cached = nameMatches[normalized] {
                    matches = cached
                } else {
                    let resolved = findMatches(in: filteredPool, normalizedQuery: normalized)
                    nameMatches[normalized] = resolved
                    matches = resolved
                }

                if let best = pickBest(from: matches, normalizedTarget: normalized, region: region) {
                    curatedResults.append(best)
                }
            }

            if curatedResults.count < 5 {
                let fallback = fallbackByRegion[region] ?? []
                for place in fallback where !curatedResults.contains(where: { $0.id == place.id }) {
                    curatedResults.append(place)
                    if curatedResults.count >= 5 { break }
                }
            }

            if curatedResults.isEmpty {
                let fallback = fallbackByRegion[region] ?? []
                curatedResults.append(contentsOf: fallback.prefix(5))
            }

            regionResults[region] = Array(curatedResults.prefix(5))
        }

        // Interleave the regional lists for the `.all` view so that
        // 1st of each region appears first (1..N), then 2nd of each (N+1..2N), etc.
        var combined: [Place] = []
        let lists = CommunityTopRatedConfig.regions.compactMap { regionResults[$0] }
        let maxLen = lists.map { $0.count }.max() ?? 0
        if maxLen > 0 {
            for i in 0..<maxLen {
                for region in CommunityTopRatedConfig.regions {
                    if let list = regionResults[region], i < list.count {
                        combined.append(list[i])
                    }
                }
            }
        }
        let dedupedCombined = deduplicateCombined(combined)
        regionResults[.all] = dedupedCombined

        return CommunityComputationResult(regionResults: regionResults)
    }

    private static func findMatches(in dataset: [Place], normalizedQuery: String) -> [Place] {
        guard !normalizedQuery.isEmpty else { return [] }

        var matches: [Place] = []
        matches.reserveCapacity(16)

        for place in dataset {
            let normalizedName = PlaceOverrides.normalizedName(for: place.name)
            if normalizedName.contains(normalizedQuery) {
                matches.append(place)
                continue
            }
            if let address = place.address {
                let normalizedAddress = PlaceOverrides.normalizedName(for: address)
                if normalizedAddress.contains(normalizedQuery) {
                    matches.append(place)
                }
            }
        }

        guard !matches.isEmpty else { return [] }
        let deduped = PlaceOverrides.deduplicate(matches)
        return PlaceOverrides.sorted(deduped)
    }

    private static func pickBest(from matches: [Place], normalizedTarget: String, region: TopRatedRegion) -> Place? {
        guard !matches.isEmpty else { return nil }
        if let exactRegional = matches.first(where: { PlaceOverrides.normalizedName(for: $0.name) == normalizedTarget && CommunityRegionClassifier.matches($0, region: region) }) {
            return exactRegional
        }
        if let regional = matches.first(where: { CommunityRegionClassifier.matches($0, region: region) }) {
            return regional
        }
        if let exact = matches.first(where: { PlaceOverrides.normalizedName(for: $0.name) == normalizedTarget }) {
            return exact
        }
        return matches.first
    }

    private static func deduplicateCombined(_ places: [Place]) -> [Place] {
        var seen = Set<String>()
        var result: [Place] = []
        result.reserveCapacity(places.count)

        for place in places {
            let key = place.id.uuidString + PlaceOverrides.normalizedName(for: place.name)
            if seen.insert(key).inserted {
                result.append(place)
            }
        }

        return result
    }
}


struct ContentView: View {
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var selectedFilter: MapFilter = .all
    @State private var bottomTab: BottomTab = .places
    @State private var selectedPlace: Place?
    @StateObject private var viewModel = MapScreenViewModel()
    @StateObject private var locationManager = LocationProvider()
    @StateObject private var appleHalalSearch = AppleHalalSearchService()
    @StateObject private var favoritesStore = FavoritesStore()
    @State private var favoritesSort: FavoritesSortOption = .recentlySaved
    @State private var topRatedSort: TopRatedSortOption = .yelp
    @State private var topRatedRegion: TopRatedRegion = .all
    @State private var hasCenteredOnUser = false
    @State private var selectedApplePlace: ApplePlaceSelection?
    @State private var searchQuery = ""
    @State private var isSearchOverlayPresented = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var previousMapRegion: MKCoordinateRegion?
    @State private var communityCache: [TopRatedRegion: [Place]] = [:]
    @State private var communityPrecomputeTask: Task<Void, Never>?
    @State private var communityComputationGeneration: Int = 0
   @State private var visiblePlaces: [Place] = []
   @State private var viewportCache = ViewportCache()
   @State private var searchDebounceTask: DispatchWorkItem?

    private let maxNewSpotsDisplayed = 10

    private let newSpotConfigs: [NewSpotConfig] = [
        NewSpotConfig(
            placeID: UUID(uuidString: "0384029a-69f2-4857-a289-36f44596cf36")!,
            imageURL: URL(string: "https://s3-media0.fl.yelpcdn.com/bphoto/cgpfmYM7TAJB3fekoQAiEA/o.jpg")!,
            displayLocation: "Tribeca, Manhattan",
            cuisine: "Indian",
            halalStatusOverride: .yes,
            openedOn: ("AUG", "25"),
            spotlightSummary: "Newest Indian fine dining with owner confirmation of halal menu.",
            spotlightBody: "Musaafer, meaning traveller, is a dining experience set in an opulent space that showcases the art and architecture of India. Chef-owner Aashim was sent on an ambitious journey through every state, gathering stories and age-old regional recipes that now appear across the menu. Guests step into TriBeCa and discover an unforgettable homage to the regions of India—custom interiors shipped from abroad and hospitality that feels like a voyage.",
            spotlightDetails: "Full Halal Menu. However, alcohol is served."
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "dcafd5ae-b276-4852-9779-f45bcb2def9e")!,
            imageURL: URL(string: "https://s3-media0.fl.yelpcdn.com/bphoto/dOPbu4vYyB728kwYCDolWg/o.jpg")!,
            photoDescription: "Prime No. 7 signature spread",
            displayLocation: "Astoria, Queens",
            cuisine: "Korean BBQ",
            halalStatusOverride: .only,
            openedOn: ("SEP", "12")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "06a506f7-e6e6-45f8-b5ed-00ffca921652")!,
            imageURL: URL(string: "https://s3-media0.fl.yelpcdn.com/bphoto/yRpkO3i-nWBM_Q4A32wzzQ/o.jpg")!,
            photoDescription: "Sma.sha signature double smash",
            displayLocation: "Long Island City, Queens",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("SEP", "13"),
            spotlightSummary: "LIC’s newest burger lab focused on halal smashburgers and seasonal specials.",
            spotlightDetails: "All beef is halal; limited seating, take-out friendly."
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "f2e7df0e-d0e9-4f21-b398-f8768639503c")!,
            imageURL: URL(string: "https://s3-media0.fl.yelpcdn.com/bphoto/YyDMa0TsyUENpJ5kY0AQPw/o.jpg")!,
            photoDescription: "Flippin Buns smash classics",
            displayLocation: "Hicksville, Long Island",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("OCT", "18")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "5765d9f5-527d-400a-b13d-6a63fbe6d707")!,
            imageURL: URL(string: "https://static-content.owner.com/funnel/images/5e65b52e-ece7-4a91-9e0a-d45a5913d7bf?v=2034024929&w=1600&q=80&auto=format")!,
            photoDescription: "Steiny B’s halal smashburger spread",
            displayLocation: "Flatbush, Brooklyn",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("AUG", "02"),
            spotlightSummary: "Flatbush smash shop named after the cheeseburger’s inventor, serving halal beef patties and Nashville hot chicken.",
            spotlightDetails: "Halal beef confirmed; small counter-service spot perfect for takeout."
        ),
        // KebabishQ — fully halal; Yelp photos imported
        NewSpotConfig(
            placeID: UUID(uuidString: "bbe55fa0-3367-4624-8b5a-e45832395b63")!,
            imageURL: URL(string: "https://s3-media0.fl.yelpcdn.com/bphoto/Zt67Wjw3J7BKIR9jHyGxoA/o.jpg")!,
            displayLocation: "East Village, Manhattan",
            cuisine: "Pakistani",
            halalStatusOverride: .only,
            openedOn: ("AUG", "06"),
            spotlightSummary: "East Village kebab spot serving a fully halal Pakistani grill menu.",
            spotlightDetails: "Fully halal. Casual counter-service with classic kebabs and grill plates."
        )
    ]

    private var halalStatusOverrides: [UUID: Place.HalalStatus] {
        var overrides: [UUID: Place.HalalStatus] = [:]
        for config in newSpotConfigs {
            if let status = config.halalStatusOverride {
                overrides[config.placeID] = status
            }
        }
        return overrides
    }

    private var newSpotEntries: [NewSpotEntry] {
        newSpotConfigs.compactMap { config in
            guard let place = viewModel.place(with: config.placeID) else { return nil }
            return NewSpotEntry(
                place: applyingOverrides(to: place),
                imageURL: config.imageURL,
                photoDescription: config.photoDescription,
                displayLocation: config.displayLocation,
                cuisine: config.cuisine,
                halalStatusOverride: config.halalStatusOverride,
                openedOn: config.openedOn,
                spotlightSummary: config.spotlightSummary,
                spotlightBody: config.spotlightBody,
                spotlightDetails: config.spotlightDetails
            )
        }
    }

    private var spotlightEntry: NewSpotEntry? {
        newSpotEntries.first(where: { $0.id == UUID(uuidString: "0384029a-69f2-4857-a289-36f44596cf36") }) ?? newSpotEntries.first
    }

    private var featuredNewSpots: [NewSpotEntry] {
        let sorted = newSpotEntries.sorted { lhs, rhs in
            sortValue(for: lhs) > sortValue(for: rhs)
        }
        guard let hero = spotlightEntry else {
            return Array(sorted.prefix(maxNewSpotsDisplayed))
        }
        guard let heroIndex = sorted.firstIndex(where: { $0.id == hero.id }) else {
            return Array(sorted.prefix(maxNewSpotsDisplayed))
        }

        var prioritized: [NewSpotEntry] = [sorted[heroIndex]]
        var remaining = sorted
        remaining.remove(at: heroIndex)
        for entry in remaining where prioritized.count < maxNewSpotsDisplayed {
            prioritized.append(entry)
        }
        return prioritized
    }

    private func sortValue(for entry: NewSpotEntry) -> Int {
        let map: [String: Int] = [
            "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
            "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12
        ]
        let month = map[entry.openedOn.month.uppercased()] ?? 0
        let day = Int(entry.openedOn.day) ?? 0
        return month * 100 + day
    }

    private var appleOverlayItems: [MKMapItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedFilter == .all else { return [] }
        guard !trimmedQuery.isEmpty else { return [] }
        guard trimmedQuery.lowercased().contains("halal") else { return [] }

        let supabaseLocations = viewModel.places.map {
            CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }

        let normalizedQuery = PlaceOverrides.normalizedName(for: trimmedQuery)

        var filtered: [MKMapItem] = []
        for item in appleHalalSearch.results {
            guard appleItemLooksHalal(item) else { continue }
            guard let coordinate = mapItemCoordinate(item) else { continue }

            // Enforce NYC + Long Island scope for Apple items
            guard RegionGate.allows(mapItem: item) else { continue }

            // Exclude known closed venues by name
            if let name = item.name, PlaceOverrides.isMarkedClosed(name: name) { continue }
            if let name = item.name, MapScreenViewModel.isBlocklistedChainName(name) { continue }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let matchesExisting = supabaseLocations.contains { existing in
                existing.distance(from: location) < 80
            }

            if matchesExisting { continue }
            if matchesAppleQuery(item: item, normalizedQuery: normalizedQuery) {
                filtered.append(item)
            }
        }

        return filtered
    }

    private func applyingOverrides(to place: Place) -> Place {
        guard let override = halalStatusOverrides[place.id], override != place.halalStatus else { return place }
        return Place(
            id: place.id,
            name: place.name,
            coordinate: place.coordinate,
            category: place.category,
            rawCategory: place.rawCategory,
            address: place.address,
            halalStatus: override,
            rating: place.rating,
            ratingCount: place.ratingCount,
            confidence: place.confidence,
            source: place.source,
            applePlaceID: place.applePlaceID,
            note: place.note,
            displayLocation: place.displayLocation
        )
    }

    private func applyingOverrides(to places: [Place]) -> [Place] {
        places.map { applyingOverrides(to: $0) }
    }

    private func appleItemLooksHalal(_ item: MKMapItem) -> Bool {
        func containsHalal(_ value: String?) -> Bool {
            guard let raw = value, !raw.isEmpty else { return false }
            let normalized = PlaceOverrides.normalizedName(for: raw)
            return normalized.contains("halal")
        }

        if containsHalal(item.name) { return true }
        if containsHalal(item.halalShortAddress) { return true }
        if let urlString = item.url?.absoluteString, containsHalal(urlString) { return true }
        if #available(iOS 13.0, *), let categoryRaw = item.pointOfInterestCategory?.rawValue {
            if containsHalal(categoryRaw) { return true }
        }
        return false
    }

    private var filteredPlaces: [Place] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.places.filteredByCurrentGeoScope() }

        let matches = viewModel.searchResults.filteredByCurrentGeoScope()
        if matches.isEmpty, viewModel.isSearching {
            return viewModel.places.filteredByCurrentGeoScope()
        }
        return matches
    }

    private var favoritesDisplay: [FavoritePlaceSnapshot] {
        let base = favoritesStore.favorites
        switch favoritesSort {
        case .recentlySaved:
            return base.sorted { lhs, rhs in
                if lhs.savedAt != rhs.savedAt {
                    return lhs.savedAt > rhs.savedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .alphabetical:
            return base.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .rating:
            return base.sorted { lhs, rhs in
                switch (lhs.rating, rhs.rating) {
                case let (l?, r?) where l != r:
                    return l > r
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    let lhsCount = lhs.ratingCount ?? 0
                    let rhsCount = rhs.ratingCount ?? 0
                    if lhsCount != rhsCount { return lhsCount > rhsCount }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    private var topRatedDisplay: [Place] {
        switch topRatedSort {
        case .yelp:
            let base = viewModel.topRatedPlaces(limit: 50, minimumReviews: 10)
            return base.filter { CommunityRegionClassifier.matches($0, region: topRatedRegion) }
        case .community:
            return communityTopRated(for: topRatedRegion)
        }
    }

    private func communityTopRated(for region: TopRatedRegion) -> [Place] {
        if let cached = communityCache[region] {
            return cached
        }
        scheduleCommunityPrecomputationIfNeeded()
        return communityFallback(for: region)
    }

    private func resetCommunityCaches() {
        communityComputationGeneration &+= 1
        communityPrecomputeTask?.cancel()
        communityPrecomputeTask = nil
        communityCache.removeAll(keepingCapacity: false)
    }

    private func communityFallback(for region: TopRatedRegion) -> [Place] {
        let base = viewModel.topRatedPlaces(limit: 60, minimumReviews: 5)
        switch region {
        case .all:
            // Build per‑region top 5 lists then interleave by rank (1st of each, then 2nd of each, etc.)
            var perRegion: [TopRatedRegion: [Place]] = [:]
            for r in CommunityTopRatedConfig.regions {
                perRegion[r] = Array(base.filter { CommunityRegionClassifier.matches($0, region: r) }.prefix(5))
            }
            var combined: [Place] = []
            let maxLen = perRegion.values.map { $0.count }.max() ?? 0
            if maxLen > 0 {
                for i in 0..<maxLen {
                    for r in CommunityTopRatedConfig.regions {
                        if let list = perRegion[r], i < list.count {
                            combined.append(list[i])
                        }
                    }
                }
            }
            return deduplicateCombinedList(combined)
        default:
            return Array(
                base
                    .filter { CommunityRegionClassifier.matches($0, region: region) }
                    .prefix(5)
            )
        }
    }

    private func deduplicateCombinedList(_ places: [Place]) -> [Place] {
        var seen = Set<String>()
        var result: [Place] = []
        result.reserveCapacity(places.count)
        for place in places {
            let key = place.id.uuidString + PlaceOverrides.normalizedName(for: place.name)
            if seen.insert(key).inserted {
                result.append(place)
            }
        }
        return result
    }

    private func scheduleCommunityPrecomputationIfNeeded(force: Bool = false) {
        if !force {
            if let cachedAll = communityCache[.all], cachedAll.count >= 5 {
                return
            }
            if communityPrecomputeTask != nil {
                return
            }
        }

        communityPrecomputeTask?.cancel()
        let snapshot = viewModel.communityTopRatedSnapshot()
        communityComputationGeneration &+= 1
        let generation = communityComputationGeneration

        communityPrecomputeTask = Task.detached(priority: .utility) {
            let result = CommunityTopRatedEngine.compute(snapshot: snapshot)
            await MainActor.run {
                guard communityComputationGeneration == generation else { return }
                for (region, list) in result.regionResults {
                    communityCache[region] = list
                }
                communityPrecomputeTask = nil
            }
        }
    }

    private var mapPlaces: [Place] {
        switch bottomTab {
        case .favorites:
            return applyingOverrides(to: favoritesDisplay.map { resolvedPlace(for: $0) })
        case .topRated:
            return applyingOverrides(to: topRatedDisplay)
        default:
            return applyingOverrides(to: visiblePlaces)
        }
    }

    private var mapAppleItems: [MKMapItem] {
        switch bottomTab {
        case .favorites, .topRated:
            return []
        default:
            return appleOverlayItems
        }
    }


    private func matchesAppleQuery(item: MKMapItem, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        if let name = item.name {
            let normalizedName = PlaceOverrides.normalizedName(for: name)
            if normalizedName.contains(normalizedQuery) { return true }
        }

        return false
    }

    private func mapItemCoordinate(_ mapItem: MKMapItem) -> CLLocationCoordinate2D? {
        let coordinate = mapItem.halalCoordinate
        if coordinate.latitude == 0 && coordinate.longitude == 0 {
            return nil
        }
        return coordinate
    }

    var body: some View {
        ZStack(alignment: .top) {
            if bottomTab == .newSpots {
                NewSpotsScreen(
                    spots: featuredNewSpots,
                    spotlight: spotlightEntry,
                    topInset: currentTopSafeAreaInset(),
                    onSelect: { place in
                        selectedPlace = place
                    }
                )
                .environmentObject(favoritesStore)
            } else {
                HalalMapView(
                    region: $mapRegion,
                    selectedPlace: $selectedPlace,
                    places: mapPlaces,
                    appleMapItems: mapAppleItems,
                    onRegionChange: { region in
                        viewModel.regionDidChange(to: region, filter: selectedFilter)
                        let effective = RegionGate.enforcedRegion(for: region)
                        appleHalalSearch.search(in: effective)
                        refreshVisiblePlaces()
                    },
                    onPlaceSelected: { place in
                        selectedPlace = place
                    },
                    onAppleItemSelected: { mapItem in
                        selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
                    },
                    onMapTap: {
                        guard bottomTab == .favorites else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            bottomTab = .places
                        }
                    }
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    searchBar
                    topSegmentedControl
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                if viewModel.isLoading && viewModel.places.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(16)
                        .background(.thinMaterial, in: Capsule())
                }

                if bottomTab == .topRated {
                    TopRatedScreen(
                        places: topRatedDisplay,
                        sortOption: topRatedSort,
                        region: topRatedRegion,
                        topInset: currentTopSafeAreaInset(),
                        bottomInset: currentBottomSafeAreaInset(),
                        onSelect: { place in
                            focus(on: place)
                        },
                        onSortChange: { topRatedSort = $0 },
                        onRegionChange: { topRatedRegion = $0 }
                    )
                    .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
                    .ignoresSafeArea()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if bottomTab != .topRated && bottomTab != .newSpots {
                locateMeButton
                    .padding(.top, locateButtonTopPadding)
                    .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .bottom) {
            bottomOverlay
        }
        .onAppear {
            viewModel.initialLoad(region: mapRegion, filter: selectedFilter)
            // Preload global dataset so New Spots can resolve specific place IDs immediately
            viewModel.ensureGlobalDataset()
            locationManager.requestAuthorizationIfNeeded()
            let effective = RegionGate.enforcedRegion(for: mapRegion)
            appleHalalSearch.search(in: effective)
            refreshVisiblePlaces()
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            guard oldValue != newValue else { return }
            viewModel.filterChanged(to: newValue, region: mapRegion)
        }
        .onChange(of: selectedPlace) { oldValue, newValue in
            guard newValue == nil, oldValue != nil else { return }
            restoreSearchStateAfterDismiss()
        }
        .onChange(of: selectedApplePlace) { oldValue, newValue in
            // Auto-ingest disabled: selecting an Apple result should not persist or mark halal.
            _ = newValue?.mapItem
            if newValue == nil, oldValue != nil {
                restoreSearchStateAfterDismiss()
            }
        }
        .onChange(of: viewModel.filteredPlacesVersion) { _ in
            resetCommunityCaches()
            if bottomTab == .topRated && topRatedSort == .community {
                scheduleCommunityPrecomputationIfNeeded(force: true)
            }
            guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard bottomTab == .places || bottomTab == .newSpots else { return }
            refreshVisiblePlaces()
        }
        .onChange(of: viewModel.searchResultsVersion) { _ in
            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard bottomTab == .places || bottomTab == .newSpots else { return }
            refreshVisiblePlaces()
        }
        .onReceive(locationManager.$lastKnownLocation.compactMap { $0 }) { location in
            guard !hasCenteredOnUser else { return }
            let span = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            let region = MKCoordinateRegion(center: location.coordinate, span: span)
            // Keep the camera focused tightly on the user's actual location
            mapRegion = region
            // But fetch/search using the enforced NYC/LI scope
            viewModel.forceRefresh(region: region, filter: selectedFilter)
            let effective = RegionGate.enforcedRegion(for: region)
            hasCenteredOnUser = true
            appleHalalSearch.search(in: effective)
            refreshVisiblePlaces()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let info = notification.userInfo,
                  let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, frameValue.height - currentBottomSafeAreaInset())
            keyboardHeight = overlap
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onChange(of: searchQuery) { _, newValue in
            searchDebounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                viewModel.search(query: "")
                searchDebounceTask = nil
                return
            }

            let workItem = DispatchWorkItem {
                viewModel.search(query: newValue)
            }
            searchDebounceTask = workItem
            workItem.notify(queue: .main) {
                if searchDebounceTask === workItem {
                    searchDebounceTask = nil
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
        .alert("Unable to load places", isPresented: $viewModel.presentingError) {
            Button("OK", role: .cancel) {
                viewModel.presentingError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unexpected error occurred.")
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
                .environmentObject(favoritesStore)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedApplePlace) { selection in
            AppleMapItemSheet(selection: selection) {
                selectedApplePlace = nil
            }
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if isSearchOverlayPresented {
                SearchOverlayView(
                    isPresented: $isSearchOverlayPresented,
                    query: $searchQuery,
                    isSearching: viewModel.isSearching,
                    supabaseResults: applyingOverrides(to: viewModel.searchResults.filteredByCurrentGeoScope()),
                    appleResults: appleOverlayItems,
                    subtitle: viewModel.subtitleMessage,
                    topSafeAreaInset: currentTopSafeAreaInset(),
                    onSelectPlace: { place in
                        focus(on: place)
                        isSearchOverlayPresented = false
                    },
                    onSelectApplePlace: { mapItem in
                        focus(on: mapItem)
                        isSearchOverlayPresented = false
                    },
                    onClear: {
                        searchQuery = ""
                    }
                )
                .ignoresSafeArea()
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onChange(of: bottomTab) { tab in
            switch tab {
            case .favorites:
                selectedApplePlace = nil
                if let selected = selectedPlace,
                   !favoritesStore.contains(id: selected.id) {
                    selectedPlace = nil
                }
            case .places:
                refreshVisiblePlaces()
            case .newSpots:
                selectedApplePlace = nil
                isSearchOverlayPresented = false
                // Ensure the global dataset is loaded so New Spots IDs resolve reliably
                viewModel.ensureGlobalDataset()
                refreshVisiblePlaces()
            case .topRated:
                selectedApplePlace = nil
                if let selected = selectedPlace,
                   !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                    selectedPlace = nil
                }
                if topRatedSort == .community {
                    scheduleCommunityPrecomputationIfNeeded()
                }
            default:
                break
            }
        }
        .onChange(of: topRatedSort) { _, newValue in
            if bottomTab == .topRated,
               let selected = selectedPlace,
               !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                selectedPlace = nil
            }
            if newValue == .community {
                scheduleCommunityPrecomputationIfNeeded()
            }
        }
        .onChange(of: topRatedRegion) { _, _ in
            if bottomTab == .topRated,
               let selected = selectedPlace,
               !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                selectedPlace = nil
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchOverlayPresented)
    }

    private var topSegmentedControl: some View {
        Picker("Category", selection: $selectedFilter) {
            ForEach(MapFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private enum BottomTab: CaseIterable, Identifiable {
        case places
        case topRated
        case newSpots
        case favorites

        var id: Self { self }

        var title: String {
            switch self {
            case .places: return "Places"
            case .topRated: return "Top Rated"
            case .newSpots: return "New Spots"
            case .favorites: return "Favorites"
            }
        }

        var systemImage: String {
            switch self {
            case .places: return "map"
            case .topRated: return "star.fill"
            case .newSpots: return "mappin.and.ellipse" // distinct; suggests new pins/places
            case .favorites: return "heart.fill"
            }
        }
    }

    private var bottomTabBar: some View {
        // Off‑white bar; keep original height but visually center content by nudging it down.
        let barHeight = max(52, currentScreenHeight() / 20)
        let safe = currentBottomSafeAreaInset()
        let contentOffset = CGFloat(min(12, max(4, safe * 0.22)))
        return VStack(spacing: 0) {
            Divider().background(Color.black.opacity(0.06))
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases) { tab in
                    Button {
                        bottomTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: contentOffset) // nudge content lower without changing bar height
                        .foregroundStyle(bottomTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: barHeight)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var bottomOverlay: some View {
        let showFavorites = bottomTab == .favorites
        return VStack(spacing: showFavorites ? 16 : 0) {
            if showFavorites {
                FavoritesPanel(
                    favorites: favoritesDisplay,
                    sortOption: favoritesSort,
                    onSelect: { snapshot in
                        focus(on: resolvedPlace(for: snapshot))
                    },
                    onSortChange: { favoritesSort = $0 }
                )
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
            }
            bottomTabBar
        }
        .padding(.bottom, bottomOverlayPadding)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: bottomTab)
    }

    private var bottomOverlayPadding: CGFloat {
        0 // flush with bottom; bar manages its own safe area
    }

    // No chip-style labels anymore; the bar uses icons + labels above.

    private var searchBar: some View {
        Button {
            isSearchOverlayPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(searchQuery.isEmpty ? "Search Halal Restaurants" : searchQuery)
                    .font(.body)
                    .foregroundStyle(searchQuery.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var locateMeButton: some View {
        Button {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestAuthorizationIfNeeded()
            case .authorizedWhenInUse, .authorizedAlways:
                if let location = locationManager.lastKnownLocation {
                    let targetRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                    // Keep the camera tight on the user's location
                    mapRegion = targetRegion
                    // Fetch/search within enforced NYC/LI scope
                    viewModel.forceRefresh(region: targetRegion, filter: selectedFilter)
                    let effective = RegionGate.enforcedRegion(for: targetRegion)
                    appleHalalSearch.search(in: effective)
                    refreshVisiblePlaces()
                } else {
                    locationManager.requestCurrentLocation()
                }
            case .denied, .restricted:
                viewModel.errorMessage = "Enable location access in Settings to jump to your position."
                viewModel.presentingError = true
            @unknown default:
                break
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 50, height: 50)
                .background(Color(.systemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
        .accessibilityLabel("Center on your location")
    }

    private var locateButtonTopPadding: CGFloat {
        let safeTop = currentTopSafeAreaInset()
        let safeBottom = currentBottomSafeAreaInset()
        let screenHeight = currentScreenHeight()
        let desiredGap: Double = 200
        let keyboardOffset = keyboardHeight > 0 ? Double(keyboardHeight) : 0
        let calculated = screenHeight - (Double(safeBottom) + desiredGap + keyboardOffset)
        return CGFloat(max(Double(safeTop) + 24, calculated))
    }

}

private extension ContentView {
    private func currentBottomSafeAreaInset() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }

    private func currentTopSafeAreaInset() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.top
    }

    func restoreSearchStateAfterDismiss() {
        previousMapRegion = nil
        if !searchQuery.isEmpty {
            searchQuery = ""
        }
    }

    func focus(on place: Place) {
        if previousMapRegion == nil {
            previousMapRegion = mapRegion
        }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: place.coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        selectedPlace = place
        isSearchOverlayPresented = false
        refreshVisiblePlaces()
    }

    func focus(on mapItem: MKMapItem) {
        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return }
        if previousMapRegion == nil {
            previousMapRegion = mapRegion
        }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let targetRegion = adjustedRegion(centeredOn: coordinate, span: span)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            mapRegion = targetRegion
        }
        selectedPlace = nil
        selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
        isSearchOverlayPresented = false
        refreshVisiblePlaces()
    }

    func resolvedPlace(for snapshot: FavoritePlaceSnapshot) -> Place {
        if let existing = viewModel.places.first(where: { $0.id == snapshot.id }) {
            return existing
        }
        if let searchMatch = viewModel.searchResults.first(where: { $0.id == snapshot.id }) {
            return searchMatch
        }
        return snapshot.toPlace()
    }

    private func adjustedRegion(centeredOn coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MKCoordinateRegion {
        var center = coordinate
        let verticalOffset = span.latitudeDelta * verticalOffsetMultiplier()
        center.latitude = clampedLatitude(center.latitude - verticalOffset, span: span)
        return MKCoordinateRegion(center: center, span: span)
    }

    private func verticalOffsetMultiplier() -> Double {
        if keyboardHeight > 0 {
            let screenHeight = max(currentScreenHeight(), 1)
            let ratio = min(1.0, Double(keyboardHeight) / screenHeight)
            return 0.28 + (0.32 * ratio)
        }
        return 0.15
    }

    private func clampedLatitude(_ latitude: Double, span: MKCoordinateSpan) -> Double {
        let halfSpan = span.latitudeDelta / 2
        let minLatitude = max(-90.0 + halfSpan, -90.0)
        let maxLatitude = min(90.0 - halfSpan, 90.0)
        return min(maxLatitude, max(minLatitude, latitude))
    }

    private func currentScreenHeight() -> Double {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return Double(activeScene.screen.bounds.height)
        }

        if let anyScene = scenes.first {
            return Double(anyScene.screen.bounds.height)
        }

        return 812 // Sensible default for calculations when no screen is available
    }

    private func refreshVisiblePlaces() {
        guard bottomTab == .places || bottomTab == .newSpots else { return }
        let base = filteredPlaces
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.isEmpty ? viewModel.filteredPlacesVersion : viewModel.searchResultsVersion
        visiblePlaces = viewportCache.slice(for: mapRegion, version: version, source: base)
    }
}

private struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @Binding var query: String
    let isSearching: Bool
    let supabaseResults: [Place]
    let appleResults: [MKMapItem]
    let subtitle: String?
    let topSafeAreaInset: CGFloat
    let onSelectPlace: (Place) -> Void
    let onSelectApplePlace: (MKMapItem) -> Void
    let onClear: () -> Void

    @FocusState private var searchFieldIsFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: topSafeAreaInset + 12)
            header
            Divider()
            content
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .onAppear {
            searchFieldIsFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                query = ""
                onClear()
                isPresented = false
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Halal Restaurants", text: $query)
                    .focused($searchFieldIsFocused)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Search halal restaurants near you")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let message = subtitle, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !supabaseResults.isEmpty {
                        Text("Halal Food matches")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(supabaseResults, id: \.id) { place in
                            Button {
                                onSelectPlace(place)
                            } label: {
                                PlaceRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !appleResults.isEmpty {
                        if !supabaseResults.isEmpty {
                            Divider()
                        }
                        Text("Apple Maps results")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(appleResults.enumerated()), id: \.offset) { _, item in
                            Button {
                                onSelectApplePlace(item)
                            } label: {
                                ApplePlaceRow(mapItem: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if supabaseResults.isEmpty && appleResults.isEmpty {
                        if isSearching {
                            HStack {
                                ProgressView()
                                Text("Searching…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No matches for \"\(trimmedQuery)\".")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct ViewportCache {
    private var lastRegion: MKCoordinateRegion?
    private var lastVersion: Int?
    private var lastResult: [Place] = []
    private var grid: SpatialGrid?

    private let movementThresholdFraction: Double = 1.0 / 3.0
    private let spanThresholdFraction: Double = 0.25
    private let paddingFactor: Double = 1.3
    private let maxCount: Int = 600
    private let gridCellSpan: Double = 0.02
    private let gridMinimumCount = 200

    mutating func slice(for region: MKCoordinateRegion, version: Int, source: [Place]) -> [Place] {
        guard !source.isEmpty else {
            lastRegion = region
            lastVersion = version
            lastResult = []
            grid = nil
            return []
        }

        if lastVersion != version {
            lastVersion = version
            lastRegion = nil
            lastResult = []
            if source.count >= gridMinimumCount {
                grid = SpatialGrid(places: source, cellSpan: gridCellSpan)
            } else {
                grid = nil
            }
        }

        if let cachedRegion = lastRegion,
           lastVersion == version,
           cachedRegion.isClose(to: region,
                                movementFraction: movementThresholdFraction,
                                spanFraction: spanThresholdFraction) {
            lastRegion = region
            return lastResult
        }

        let candidates: [Place]
        if let grid {
            candidates = grid.query(region: region, paddingFactor: paddingFactor)
        } else {
            candidates = source
        }

        let filtered = filterCandidates(candidates, in: region, paddingFactor: paddingFactor)
        let trimmed = trim(filtered, in: region, limit: maxCount)
        lastRegion = region
        lastResult = trimmed
        return trimmed
    }

    private func filterCandidates(_ places: [Place],
                                  in region: MKCoordinateRegion,
                                  paddingFactor: Double) -> [Place] {
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return places }
        let halfLat = (region.span.latitudeDelta * paddingFactor) / 2.0
        let halfLon = (region.span.longitudeDelta * paddingFactor) / 2.0
        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        return places.filter { place in
            let lat = place.coordinate.latitude
            let lon = place.coordinate.longitude
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
    }

    private func trim(_ places: [Place],
                      in region: MKCoordinateRegion,
                      limit: Int) -> [Place] {
        guard places.count > limit else { return places }
        let center = region.center
        let sorted = places.sorted {
            center.squaredDistance(to: $0.coordinate) < center.squaredDistance(to: $1.coordinate)
        }
        return Array(sorted.prefix(limit))
    }
}

private struct SpatialGrid {
    private struct Tile: Hashable {
        let x: Int
        let y: Int

        static func index(for value: Double, span: Double) -> Int {
            Int(floor(value / span))
        }

        init(coordinate: CLLocationCoordinate2D, cellSpan: Double) {
            self.x = Tile.index(for: coordinate.longitude, span: cellSpan)
            self.y = Tile.index(for: coordinate.latitude, span: cellSpan)
        }

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    private let cellSpan: Double
    private let buckets: [Tile: [Place]]

    init(places: [Place], cellSpan: Double) {
        self.cellSpan = cellSpan
        var storage: [Tile: [Place]] = [:]
        storage.reserveCapacity(max(1, places.count / 4))
        for place in places {
            let tile = Tile(coordinate: place.coordinate, cellSpan: cellSpan)
            storage[tile, default: []].append(place)
        }
        self.buckets = storage
    }

    func query(region: MKCoordinateRegion, paddingFactor: Double) -> [Place] {
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return [] }
        let halfLat = (region.span.latitudeDelta * paddingFactor) / 2.0
        let halfLon = (region.span.longitudeDelta * paddingFactor) / 2.0

        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        let minX = Tile.index(for: minLon, span: cellSpan)
        let maxX = Tile.index(for: maxLon, span: cellSpan)
        let minY = Tile.index(for: minLat, span: cellSpan)
        let maxY = Tile.index(for: maxLat, span: cellSpan)

        guard minX <= maxX, minY <= maxY else { return [] }

        var results: [Place] = []
        results.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        var seen: Set<UUID> = []

        for x in minX...maxX {
            for y in minY...maxY {
                if let bucket = buckets[Tile(x: x, y: y)] {
                    for place in bucket where seen.insert(place.id).inserted {
                        results.append(place)
                    }
                }
            }
        }

        return results
    }
}

private extension MKCoordinateRegion {
    func isClose(to other: MKCoordinateRegion,
                 movementFraction: Double,
                 spanFraction: Double) -> Bool {
        let latThreshold = max(max(span.latitudeDelta, other.span.latitudeDelta), 1e-6) * movementFraction
        let lonThreshold = max(max(span.longitudeDelta, other.span.longitudeDelta), 1e-6) * movementFraction
        let latDiff = abs(center.latitude - other.center.latitude)
        let lonDiff = abs(center.longitude - other.center.longitude)
        guard latDiff <= latThreshold, lonDiff <= lonThreshold else { return false }

        let latSpanThreshold = max(max(span.latitudeDelta, other.span.latitudeDelta), 1e-6) * spanFraction
        let lonSpanThreshold = max(max(span.longitudeDelta, other.span.longitudeDelta), 1e-6) * spanFraction
        let latSpanDiff = abs(span.latitudeDelta - other.span.latitudeDelta)
        let lonSpanDiff = abs(span.longitudeDelta - other.span.longitudeDelta)
        return latSpanDiff <= latSpanThreshold && lonSpanDiff <= lonSpanThreshold
    }
}

private extension CLLocationCoordinate2D {
    func squaredDistance(to other: CLLocationCoordinate2D) -> Double {
        let latDiff = latitude - other.latitude
        let lonDiff = longitude - other.longitude
        return latDiff * latDiff + lonDiff * lonDiff
    }
}

private struct PlaceRow: View {
    let place: Place

    private let detailColor = Color.primary.opacity(0.75)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let iconName = place.category == .restaurant ? "fork.knife.circle.fill" : "mappin.circle.fill"
            let iconColor: Color = {
                switch place.halalStatus {
                case .only:
                    return .green
                case .yes:
                    return .orange
                case .unknown:
                    return .gray
                case .no:
                    return .red
                }
            }()
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.headline)
                if let address = place.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                }
                Text(place.halalStatus.label.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                if let rating = place.rating {
                    let count = place.ratingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("(\(count) \(ratingLabel))")
                        if let source = place.source, !source.isEmpty {
                            Text("- \(readableSource(source))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                } else if let source = place.source, !source.isEmpty {
                    Text(readableSource(source))
                        .font(.caption2)
                        .foregroundStyle(detailColor)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func readableSource(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { component -> String in
            let lower = component.lowercased()
            switch lower {
            case "yelp": return "Yelp"
            case "apple": return "Apple"
            case "manual": return "Manual"
            default: return lower.capitalized
            }
        }
        .joined(separator: " ")
}

private struct ApplePlaceRow: View {
    let mapItem: MKMapItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(mapItem.name ?? "Apple Maps Place")
                    .font(.headline)

                if let address = mapItem.halalShortAddress {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Apple Maps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TopRatedScreen: View {
    let places: [Place]
    let sortOption: TopRatedSortOption
    let region: TopRatedRegion
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onSelect: (Place) -> Void
    let onSortChange: (TopRatedSortOption) -> Void
    let onRegionChange: (TopRatedRegion) -> Void

    private let detailColor = Color.primary.opacity(0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Rated")
                        .font(.title3.weight(.semibold))
                    if !places.isEmpty {
                        Text("\(places.count) places")
                            .font(.caption)
                            .foregroundStyle(detailColor)
                    }
                }

                Spacer()

                Menu {
                    ForEach(TopRatedRegion.allCases) { option in
                        Button(option.title) {
                            onRegionChange(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("By Location")
                        if region != .all {
                            Text(region.title)
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(TopRatedSortOption.allCases) { option in
                    sortButton(for: option)
                }
                Spacer(minLength: 0)
            }

            if places.isEmpty {
                Text("No matches yet. Try a different location.")
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Card style similar to NewSpots
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                                if index != 0 {
                                    Divider()
                                        .background(Color.black.opacity(0.06))
                                }
                                Button { onSelect(place) } label: {
                                    TopRatedRow(
                                        place: place,
                                        rank: (sortOption == .community ? index + 1 : nil),
                                        showYelpRating: sortOption != .community
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(18)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 9)
                    }
                    .padding(.vertical, 8)
                }
                .task(id: places.map { $0.id }) {
                    // Warm prefetch a small number of thumbnails for instant display
                    for id in places.prefix(20).map({ $0.id }) {
                        TopRatedPhotoThumb.prefetch(for: id)
                    }
                }
            }
        }
        .padding(.top, topInset + 24)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomInset + 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private func sortButton(for option: TopRatedSortOption) -> some View {
        let isSelected = option == sortOption
        return Button {
            onSortChange(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : detailColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct TopRatedRow: View {
    let place: Place
    let rank: Int?
    let showYelpRating: Bool

    private let detailColor = Color.primary.opacity(0.75)
    @State private var cuisine: String?
    @State private var displayLocOverride: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TopRatedPhotoThumb(placeID: place.id)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                if showYelpRating {
                    ratingView()
                }

                Text(categoryLine())
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                if let loc = shortLocation() {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .overlay(alignment: .topTrailing) {
            if let rank { rankBadge(rank) }
        }
        .task(id: place.id) {
            await loadCuisine()
        }
    }

    @ViewBuilder
    private func ratingView() -> some View {
        if let rating = place.rating {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                Text(String(format: "%.1f", rating))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                Text("(\(reviewLabel(for: place.ratingCount)))")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func reviewLabel(for count: Int?) -> String {
        guard let count else { return "No reviews" }
        if count == 1 { return "1 review" }
        if count >= 1000 { return String(format: "%.1fk reviews", Double(count) / 1000.0) }
        return "\(count) reviews"
    }

    private func categoryLine() -> String {
        // Show cuisine if fetched; otherwise just halal label
        let halalLabel = place.halalStatus == .only ? "Fully halal" : place.halalStatus.label
        if let cuisine { return "\(cuisine) • \(halalLabel)" }
        return halalLabel
    }

    private struct SourceRow: Decodable {
        let display_location: String?
        let source_raw: SourceRaw?
    }
    private struct SourceRaw: Decodable { let categories: [String]?, display_location: String? }

    private func titleCase(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    @MainActor
    private func loadCuisine() async {
        if displayLocOverride == nil {
            displayLocOverride = place.displayLocation ?? DisplayLocationResolver.display(for: place)
        }
        do {
            var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
            var p = comps.path
            if !p.hasSuffix("/") { p.append("/") }
            p.append("rest/v1/place")
            comps.path = p
            comps.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(place.id.uuidString)"),
                URLQueryItem(name: "select", value: "source_raw,display_location")
            ]
            var req = URLRequest(url: comps.url!)
            let key = Env.anonKey
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let row = try? JSONDecoder().decode([SourceRow].self, from: data).first {
                    if let categories = row.source_raw?.categories {
                        cuisine = preferredCuisine(from: categories)
                    }
                    if let disp = row.display_location?.trimmingCharacters(in: .whitespacesAndNewlines), !disp.isEmpty {
                        displayLocOverride = disp
                    } else if let disp = row.source_raw?.display_location, !disp.isEmpty {
                        displayLocOverride = disp
                    } else if displayLocOverride == nil {
                        displayLocOverride = DisplayLocationResolver.display(for: place)
                    }
                }
            }
        } catch {
            // ignore
        }
    }

    private func preferredCuisine(from categories: [String]) -> String? {
        // Normalize
        let cats = categories.map { $0.lowercased() }

        // Skip non-cuisine categories and generic tags
        let excluded: Set<String> = [
            "halal","gluten_free","vegan","vegetarian",
            "coffee","cafes","coffeeandtea","tea","bubbletea",
            "desserts","donuts","bakeries","icecream",
            "bars","cocktailbars","beerbar","wine_bars"
        ]

        // Map Yelp aliases to display labels
        let map: [String: String] = {
            var map: [String: String] = [:]
            map["thai"] = "Thai"
            map["lebanese"] = "Lebanese"
            map["mediterranean"] = "Mediterranean"
            map["turkish"] = "Turkish"
            map["middleeastern"] = "Middle Eastern"
            map["arabian"] = "Middle Eastern"
            map["indpak"] = "Indian"
            map["indian"] = "Indian"
            map["pakistani"] = "Pakistani"
            map["bangladeshi"] = "Bangladeshi"
            map["afghani"] = "Afghan"
            map["himalayan"] = "Himalayan"
            map["nepalese"] = "Nepalese"
            map["chinese"] = "Chinese"
            map["japanese"] = "Japanese"
            map["korean"] = "Korean"
            map["vietnamese"] = "Vietnamese"
            map["italian"] = "Italian"
            map["mexican"] = "Mexican"
            map["ethiopian"] = "Ethiopian"
            map["persian"] = "Persian"
            map["iranian"] = "Persian"
            map["uzbek"] = "Uzbek"
            map["bbq"] = "BBQ"
            map["pizza"] = "Pizza"
            map["burgers"] = "Burgers"
            map["sandwiches"] = "Sandwiches"
            map["seafood"] = "Seafood"
            map["chicken_wings"] = "Chicken Wings"
            return map
        }()

        // 1) Pick first mapped cuisine that's not excluded
        for c in cats where !excluded.contains(c) {
            if let label = map[c] {
                return label
            }
        }

        // 2) If not found, pick any non-excluded, title-cased
        if let first = cats.first(where: { !excluded.contains($0) }) {
            let label = titleCase(first)
            return label
        }
        return nil
    }

    private func shortLocation() -> String? {
        if let override = displayLocOverride, !override.isEmpty { return override }
        if let persisted = place.displayLocation, !persisted.isEmpty { return persisted }
        return DisplayLocationResolver.display(for: place)
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        let symbolName: String? = rank <= 50 ? "\(rank).circle.fill" : nil
        let gold = Color(red: 0.95, green: 0.76, blue: 0.20)
        return HStack(spacing: 6) {
            if rank == 1 { Text("🏆").font(.system(size: 14)) }
            Group {
                if let name = symbolName, UIImage(systemName: name) != nil {
                    Image(systemName: name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(gold)
                } else {
                    Text("\(rank)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(gold.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(gold.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(gold)
                }
            }
        }
        .padding(.top, 4)
        .padding(.trailing, 4)
    }
}

// MARK: - Display Location Resolver (Neighborhood, Borough) with caching
private enum DisplayLocationResolver {
    static func display(for place: Place) -> String? {
        if let cached = DisplayLocationCache.shared.get(placeID: place.id) { return cached }
        guard let address = place.address, !address.isEmpty else { return nil }

        let lower = address.lowercased()
        let zip = extractZip(from: address)
        let borough = detectBorough(in: lower, zip: zip)

        let result: String
        let neigh = detectNeighborhood(in: lower, zip: zip)
        if let borough, let neighborhood = neigh, !neighborhood.caseInsensitiveEquals(borough) {
            result = "\(neighborhood.capitalizedWords()), \(borough)"
        } else if let borough {
            result = borough
        } else {
            // Fallback to penultimate token
            let comps = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if comps.count >= 2 { result = comps[comps.count - 2] } else { result = address }
        }

        DisplayLocationCache.shared.set(placeID: place.id, value: result)
        return result
    }

    private static func extractZip(from address: String) -> String? {
        // Find last 5-digit number
        let digits = address.reversed().split(whereSeparator: { !$0.isNumber }).first
        let zipRev = digits.map(String.init)
        guard let rev = zipRev, rev.count >= 5 else { return nil }
        let zip = String(rev.prefix(5).reversed())
        return zip.count == 5 ? zip : nil
    }

    private static func detectBorough(in lowerAddress: String, zip: String?) -> String? {
        if let zip, zip.count == 5 {
            if zip.hasPrefix("112") { return "Brooklyn" }
            if zip.hasPrefix("111") || zip.hasPrefix("113") || zip.hasPrefix("114") || zip.hasPrefix("116") { return "Queens" }
            if zip.hasPrefix("104") { return "Bronx" }
            if zip.hasPrefix("103") { return "Staten Island" }
            if zip.hasPrefix("100") || zip.hasPrefix("101") || zip.hasPrefix("102") { return "Manhattan" }
            if zip.hasPrefix("110") || zip.hasPrefix("115") || zip.hasPrefix("117") || zip.hasPrefix("118") || zip.hasPrefix("119") { return "Long Island" }
        }
        if lowerAddress.contains(" brooklyn") { return "Brooklyn" }
        if lowerAddress.contains(" queens") { return "Queens" }
        if lowerAddress.contains(" bronx") { return "Bronx" }
        if lowerAddress.contains(" staten island") { return "Staten Island" }
        if lowerAddress.contains(" new york") { return "Manhattan" }
        return nil
    }

    private static func detectNeighborhood(in lowerAddress: String, zip: String? = nil) -> String? {
        if let z = zip, let mapped = zipNeighborhoodOverride[z] { return mapped }
        for (token, pretty, _) in neighborhoods where lowerAddress.contains(token) {
            return pretty
        }
        return nil
    }

    // token (lowercased), pretty label, borough
    private static let neighborhoods: [(String, String, String)] = [
        // Manhattan
        ("tribeca", "Tribeca", "Manhattan"),
        ("soho", "SoHo", "Manhattan"),
        ("greenwich village", "Greenwich Village", "Manhattan"),
        ("east village", "East Village", "Manhattan"),
        ("west village", "West Village", "Manhattan"),
        ("lower east side", "Lower East Side", "Manhattan"),
        ("harlem", "Harlem", "Manhattan"),
        ("washington heights", "Washington Heights", "Manhattan"),
        ("inwood", "Inwood", "Manhattan"),
        ("chelsea", "Chelsea", "Manhattan"),
        ("midtown", "Midtown", "Manhattan"),
        ("murray hill", "Murray Hill", "Manhattan"),
        ("gramercy", "Gramercy", "Manhattan"),
        ("financial district", "Financial District", "Manhattan"),
        ("fidi", "Financial District", "Manhattan"),
        ("upper east side", "Upper East Side", "Manhattan"),
        ("upper west side", "Upper West Side", "Manhattan"),

        // Queens
        ("sunnyside", "Sunnyside", "Queens"),
        ("astoria", "Astoria", "Queens"),
        ("long island city", "Long Island City", "Queens"),
        (" lic ", "Long Island City", "Queens"),
        ("jackson heights", "Jackson Heights", "Queens"),
        ("flushing", "Flushing", "Queens"),
        ("jamaica, ny", "Jamaica", "Queens"),
        ("woodside", "Woodside", "Queens"),
        ("elmhurst", "Elmhurst", "Queens"),
        ("forest hills", "Forest Hills", "Queens"),
        ("rego park", "Rego Park", "Queens"),
        ("kew gardens", "Kew Gardens", "Queens"),
        ("richmond hill", "Richmond Hill", "Queens"),
        ("ozone park", "Ozone Park", "Queens"),
        ("bayside", "Bayside", "Queens"),
        ("whitestone", "Whitestone", "Queens"),
        ("college point", "College Point", "Queens"),
        ("far rockaway", "Far Rockaway", "Queens"),
        (" rockaway", "Rockaway", "Queens"),

        // Brooklyn
        ("williamsburg", "Williamsburg", "Brooklyn"),
        ("greenpoint", "Greenpoint", "Brooklyn"),
        ("bed-stuy", "Bed-Stuy", "Brooklyn"),
        ("bedford-stuyvesant", "Bedford-Stuyvesant", "Brooklyn"),
        ("bushwick", "Bushwick", "Brooklyn"),
        ("park slope", "Park Slope", "Brooklyn"),
        ("sunset park", "Sunset Park", "Brooklyn"),
        ("downtown brooklyn", "Downtown Brooklyn", "Brooklyn"),
        ("bay ridge", "Bay Ridge", "Brooklyn"),
        ("dyker heights", "Dyker Heights", "Brooklyn"),
        ("flatbush", "Flatbush", "Brooklyn"),
        ("crown heights", "Crown Heights", "Brooklyn"),
        ("brighton beach", "Brighton Beach", "Brooklyn"),
        ("sheepshead bay", "Sheepshead Bay", "Brooklyn"),
        ("brooklyn heights", "Brooklyn Heights", "Brooklyn"),
        ("dumbo", "DUMBO", "Brooklyn"),
        ("fort greene", "Fort Greene", "Brooklyn"),
        ("clinton hill", "Clinton Hill", "Brooklyn"),
        ("prospect heights", "Prospect Heights", "Brooklyn"),
        ("carroll gardens", "Carroll Gardens", "Brooklyn"),
        ("cobble hill", "Cobble Hill", "Brooklyn"),
        ("boerum hill", "Boerum Hill", "Brooklyn"),

        // Bronx
        ("riverdale", "Riverdale", "Bronx"),
        ("kingsbridge", "Kingsbridge", "Bronx"),
        ("fordham", "Fordham", "Bronx"),
        ("mott haven", "Mott Haven", "Bronx"),
        ("pelham bay", "Pelham Bay", "Bronx"),
        ("throgs neck", "Throgs Neck", "Bronx"),

        // Staten Island
        ("st. george", "St. George", "Staten Island"),
        ("st george", "St. George", "Staten Island"),
        ("westerleigh", "Westerleigh", "Staten Island")
    ]
    private static let zipNeighborhoodOverride: [String: String] = {
        var map: [String: String] = [:]
        map["06390"] = "Unknown"
        map["063HH"] = "Unknown"
        map["10001"] = "Hudson Yards"
        map["10002"] = "Two Bridges"
        map["10003"] = "East Village"
        map["10004"] = "Financial District"
        map["10005"] = "Financial District"
        map["10006"] = "Financial District"
        map["10007"] = "Civic Center"
        map["10009"] = "East Village"
        map["10010"] = "Kips Bay"
        map["10011"] = "Flatiron"
        map["10012"] = "Nolita"
        map["10013"] = "Chinatown"
        map["10014"] = "West Village"
        map["10016"] = "Midtown East"
        map["10017"] = "Midtown East"
        map["10018"] = "Theater District"
        map["10019"] = "Midtown West"
        map["10020"] = "New York"
        map["10021"] = "Upper East Side"
        map["10022"] = "Midtown East"
        map["10023"] = "Upper West Side"
        map["10024"] = "Upper West Side"
        map["10025"] = "Morningside Heights"
        map["10026"] = "Harlem"
        map["10027"] = "Harlem"
        map["10028"] = "Upper East Side"
        map["10029"] = "East Harlem"
        map["10030"] = "Harlem"
        map["10031"] = "New York"
        map["10032"] = "Washington Heights"
        map["10033"] = "Washington Heights"
        map["10034"] = "Inwood"
        map["10035"] = "East Harlem"
        map["10036"] = "Theater District"
        map["10037"] = "Harlem"
        map["10038"] = "Financial District"
        map["10039"] = "Harlem"
        map["10040"] = "Washington Heights"
        map["10041"] = "New York"
        map["10044"] = "Roosevelt Island"
        map["10048"] = "New York"
        map["10065"] = "Upper East Side"
        map["10069"] = "Upper West Side"
        map["10075"] = "Upper East Side"
        map["100HH"] = "New York"
        map["10103"] = "New York"
        map["10111"] = "New York"
        map["10112"] = "New York"
        map["10115"] = "New York"
        map["10119"] = "New York"
        map["10128"] = "Upper East Side"
        map["10152"] = "New York"
        map["10153"] = "New York"
        map["10154"] = "New York"
        map["10162"] = "New York"
        map["10165"] = "New York"
        map["10167"] = "New York"
        map["10169"] = "New York"
        map["10170"] = "New York"
        map["10171"] = "New York"
        map["10172"] = "New York"
        map["10173"] = "New York"
        map["10177"] = "New York"
        map["10271"] = "New York"
        map["10278"] = "New York"
        map["10279"] = "New York"
        map["10280"] = "Battery Park City"
        map["10282"] = "Battery Park City"
        map["102HH"] = "Zcta 102hh"
        map["10301"] = "St. George / Tompkinsville"
        map["10302"] = "Port Richmond / Mariners Harbor"
        map["10303"] = "Port Richmond / Mariners Harbor"
        map["10304"] = "Stapleton / Clifton"
        map["10305"] = "Dongan Hills / Grant City"
        map["10306"] = "New Dorp / Midland Beach"
        map["10307"] = "Tottenville"
        map["10308"] = "Great Kills"
        map["10309"] = "Staten Island"
        map["10310"] = "New Brighton / West Brighton"
        map["10312"] = "Huguenot / Prince's Bay"
        map["10314"] = "New Springville / Willowbrook"
        map["103HH"] = "Zcta 103hh"
        map["10451"] = "Concourse / Concourse Village"
        map["10452"] = "Concourse / Concourse Village"
        map["10453"] = "University Heights"
        map["10454"] = "Port Morris"
        map["10455"] = "Longwood"
        map["10456"] = "Morrisania"
        map["10457"] = "Bronx"
        map["10458"] = "Belmont"
        map["10459"] = "Longwood"
        map["10460"] = "Bronx"
        map["10461"] = "Pelham Bay"
        map["10462"] = "Castle Hill"
        map["10463"] = "Kingsbridge"
        map["10464"] = "City Island"
        map["10465"] = "Country Club"
        map["10466"] = "Wakefield"
        map["10467"] = "Norwood"
        map["10468"] = "Fordham / Bedford Park"
        map["10469"] = "Pelham Gardens"
        map["10470"] = "Wakefield"
        map["10471"] = "Riverdale"
        map["10472"] = "Soundview / Clason Point"
        map["10473"] = "Castle Hill"
        map["10474"] = "Hunts Point"
        map["10475"] = "Co-op City"
        map["104HH"] = "Zcta 104hh"
        map["11001"] = "Floral Park"
        map["11003"] = "Alden Manor"
        map["11004"] = "Glen Oaks"
        map["11005"] = "Floral Park"
        map["11010"] = "Franklin Square"
        map["11020"] = "Great Neck"
        map["11021"] = "Great Neck"
        map["11023"] = "Great Neck"
        map["11024"] = "Kings Point Cont"
        map["11030"] = "Plandome"
        map["11040"] = "Hillside Manor"
        map["11042"] = "New Hyde Park"
        map["11050"] = "Port Washington"
        map["11096"] = "Zcta 11096"
        map["110HH"] = "Zcta 110hh"
        map["11101"] = "Long Island City"
        map["11102"] = "Astoria"
        map["11103"] = "Astoria"
        map["11104"] = "Sunnyside"
        map["11105"] = "Astoria"
        map["11106"] = "Astoria"
        map["11109"] = "Long Island City"
        map["111HH"] = "Zcta 111hh"
        map["11201"] = "Downtown Brooklyn"
        map["11203"] = "East Flatbush"
        map["11204"] = "Bensonhurst"
        map["11205"] = "Clinton Hill"
        map["11206"] = "Bedford–Stuyvesant"
        map["11207"] = "East New York"
        map["11208"] = "East New York"
        map["11209"] = "Bay Ridge"
        map["11210"] = "Midwood"
        map["11211"] = "Williamsburg"
        map["11212"] = "Brownsville"
        map["11213"] = "Crown Heights"
        map["11214"] = "Gravesend"
        map["11215"] = "Park Slope"
        map["11216"] = "Crown Heights"
        map["11217"] = "Downtown Brooklyn"
        map["11218"] = "Kensington"
        map["11219"] = "Borough Park"
        map["11220"] = "Sunset Park"
        map["11221"] = "Bedford–Stuyvesant"
        map["11222"] = "Greenpoint"
        map["11223"] = "Gravesend"
        map["11224"] = "Coney Island"
        map["11225"] = "Crown Heights"
        map["11226"] = "Flatbush"
        map["11228"] = "Dyker Heights"
        map["11229"] = "Brooklyn"
        map["11230"] = "Midwood"
        map["11231"] = "Red Hook"
        map["11232"] = "Sunset Park"
        map["11233"] = "Bedford–Stuyvesant"
        map["11234"] = "Marine Park"
        map["11235"] = "Brighton Beach"
        map["11236"] = "Canarsie"
        map["11237"] = "Bushwick"
        map["11238"] = "Clinton Hill"
        map["11239"] = "Brooklyn"
        map["11249"] = "Williamsburg"
        map["112HH"] = "Zcta 112hh"
        map["11354"] = "Flushing"
        map["11355"] = "Flushing"
        map["11356"] = "College Point"
        map["11357"] = "Whitestone"
        map["11358"] = "Auburndale"
        map["11360"] = "Bayside"
        map["11361"] = "Bayside"
        map["11362"] = "Little Neck"
        map["11363"] = "Little Neck"
        map["11364"] = "Oakland Gardens"
        map["11365"] = "Fresh Meadows"
        map["11366"] = "Fresh Meadows"
        map["11367"] = "Flushing"
        map["11368"] = "Corona"
        map["11369"] = "East Elmhurst"
        map["11370"] = "East Elmhurst"
        map["11371"] = "Flushing"
        map["11372"] = "Jackson Heights"
        map["11373"] = "Elmhurst"
        map["11374"] = "Rego Park"
        map["11375"] = "Forest Hills"
        map["11377"] = "Woodside"
        map["11378"] = "Maspeth"
        map["11379"] = "Middle Village"
        map["11385"] = "Ridgewood"
        map["113HH"] = "Zcta 113hh"
        map["11411"] = "Cambria Heights / Laurelton"
        map["11412"] = "St. Albans / Hollis"
        map["11413"] = "Cambria Heights / Laurelton"
        map["11414"] = "Howard Beach"
        map["11415"] = "Kew Gardens"
        map["11416"] = "Ozone Park"
        map["11417"] = "Ozone Park"
        map["11418"] = "Richmond Hill"
        map["11419"] = "Richmond Hill"
        map["11420"] = "South Ozone Park"
        map["11421"] = "Woodhaven"
        map["11422"] = "Rosedale"
        map["11423"] = "St. Albans / Hollis"
        map["11426"] = "Bellerose"
        map["11427"] = "Queens Village"
        map["11428"] = "Queens Village"
        map["11429"] = "Queens Village"
        map["11430"] = "Jamaica"
        map["11432"] = "Jamaica"
        map["11433"] = "Jamaica"
        map["11434"] = "Jamaica"
        map["11435"] = "Jamaica"
        map["11436"] = "Jamaica"
        map["114HH"] = "Zcta 114hh"
        map["11501"] = "Mineola"
        map["11507"] = "Albertson"
        map["11509"] = "Atlantic Beach"
        map["11510"] = "Baldwin"
        map["11514"] = "Carle Place"
        map["11516"] = "Cedarhurst"
        map["11518"] = "East Rockaway"
        map["11520"] = "Freeport"
        map["11530"] = "Garden City"
        map["11542"] = "Glen Cove"
        map["11545"] = "Glen Head"
        map["11547"] = "Glenwood Landing"
        map["11548"] = "Greenvale"
        map["11550"] = "Hempstead"
        map["11552"] = "West Hempstead"
        map["11553"] = "Uniondale"
        map["11554"] = "East Meadow"
        map["11557"] = "Hewlett"
        map["11558"] = "Island Park"
        map["11559"] = "Lawrence"
        map["11560"] = "Locust Valley"
        map["11561"] = "Long Beach"
        map["11563"] = "Lynbrook"
        map["11565"] = "Malverne"
        map["11566"] = "North Merrick"
        map["11568"] = "Old Westbury"
        map["11569"] = "Point Lookout"
        map["11570"] = "Rockville Centre"
        map["11572"] = "Oceanside"
        map["11575"] = "Roosevelt"
        map["11576"] = "Roslyn"
        map["11577"] = "Roslyn Heights"
        map["11579"] = "Sea Cliff"
        map["11580"] = "Valley Stream"
        map["11581"] = "North Woodmere"
        map["11590"] = "Westbury"
        map["11596"] = "Williston Park"
        map["11598"] = "Woodmere"
        map["115HH"] = "Zcta 115hh"
        map["11691"] = "The Rockaways"
        map["11692"] = "The Rockaways"
        map["11693"] = "The Rockaways"
        map["11694"] = "The Rockaways"
        map["11695"] = "The Rockaways"
        map["11697"] = "The Rockaways"
        map["116HH"] = "Zcta 116hh"
        map["11701"] = "Amityville"
        map["11702"] = "Oak Beach"
        map["11703"] = "North Babylon"
        map["11704"] = "West Babylon"
        map["11705"] = "Bayport"
        map["11706"] = "Kismet"
        map["11709"] = "Bayville"
        map["11710"] = "North Bellmore"
        map["11713"] = "Bellport"
        map["11714"] = "Bethpage"
        map["11715"] = "Blue Point"
        map["11716"] = "Bohemia"
        map["11717"] = "West Brentwood"
        map["11718"] = "Brightwaters"
        map["11719"] = "Brookhaven"
        map["11720"] = "Centereach"
        map["11721"] = "Centerport"
        map["11722"] = "Central Islip"
        map["11724"] = "Cold Spring Harb"
        map["11725"] = "Commack"
        map["11726"] = "Copiague"
        map["11727"] = "Coram"
        map["11729"] = "Deer Park"
        map["11730"] = "East Islip"
        map["11731"] = "Elwood"
        map["11732"] = "East Norwich"
        map["11733"] = "Setauket"
        map["11735"] = "South Farmingdal"
        map["11738"] = "Farmingville"
        map["11740"] = "Greenlawn"
        map["11741"] = "Holbrook"
        map["11742"] = "Holtsville"
        map["11743"] = "Halesite"
        map["11746"] = "Dix Hills"
        map["11747"] = "Melville"
        map["11751"] = "Islip"
        map["11752"] = "Islip Terrace"
        map["11753"] = "Jericho"
        map["11754"] = "Kings Park"
        map["11755"] = "Lake Grove"
        map["11756"] = "Levittown"
        map["11757"] = "Lindenhurst"
        map["11758"] = "North Massapequa"
        map["11762"] = "Massapequa Park"
        map["11763"] = "Medford"
        map["11764"] = "Miller Place"
        map["11765"] = "Mill Neck"
        map["11766"] = "Mount Sinai"
        map["11767"] = "Nesconset"
        map["11768"] = "Northport"
        map["11769"] = "Oakdale"
        map["11770"] = "Ocean Beach"
        map["11771"] = "Oyster Bay"
        map["11772"] = "Davis Park"
        map["11776"] = "Port Jefferson S"
        map["11777"] = "Port Jefferson"
        map["11778"] = "Rocky Point"
        map["11779"] = "Lake Ronkonkoma"
        map["11780"] = "Saint James"
        map["11782"] = "Cherry Grove"
        map["11783"] = "Seaford"
        map["11784"] = "Selden"
        map["11786"] = "Shoreham"
        map["11787"] = "Smithtown"
        map["11788"] = "Hauppauge"
        map["11789"] = "Sound Beach"
        map["11790"] = "Stony Brook"
        map["11791"] = "Syosset"
        map["11792"] = "Wading River"
        map["11793"] = "Wantagh"
        map["11795"] = "West Islip"
        map["11796"] = "West Sayville"
        map["11797"] = "Woodbury"
        map["11798"] = "Wheatley Heights"
        map["117HH"] = "Zcta 117hh"
        map["11801"] = "Hicksville"
        map["11803"] = "Plainview"
        map["11804"] = "Old Bethpage"
        map["11901"] = "Riverhead"
        map["11930"] = "Amagansett"
        map["11932"] = "Bridgehampton"
        map["11933"] = "Calverton"
        map["11934"] = "Center Moriches"
        map["11935"] = "Cutchogue"
        map["11937"] = "East Hampton"
        map["11939"] = "East Marion"
        map["11940"] = "East Moriches"
        map["11941"] = "Eastport"
        map["11942"] = "East Quogue"
        map["11944"] = "Greenport"
        map["11946"] = "Hampton Bays"
        map["11947"] = "Jamesport"
        map["11948"] = "Laurel"
        map["11949"] = "Manorville"
        map["11950"] = "Mastic"
        map["11951"] = "Mastic Beach"
        map["11952"] = "Mattituck"
        map["11953"] = "Middle Island"
        map["11954"] = "Montauk"
        map["11955"] = "Moriches"
        map["11956"] = "New Suffolk"
        map["11957"] = "Orient"
        map["11958"] = "Peconic"
        map["11959"] = "Quogue"
        map["11960"] = "Remsenburg"
        map["11961"] = "Ridge"
        map["11962"] = "Sagaponack"
        map["11963"] = "Sag Harbor"
        map["11964"] = "Shelter Island"
        map["11965"] = "Shelter Island H"
        map["11967"] = "Shirley"
        map["11968"] = "Southampton"
        map["11970"] = "South Jamesport"
        map["11971"] = "Southold"
        map["11972"] = "Speonk"
        map["11975"] = "Wainscott"
        map["11976"] = "Water Mill"
        map["11977"] = "Westhampton"
        map["11978"] = "Westhampton Beac"
        map["11980"] = "Yaphank"
        map["119HH"] = "Zcta 119hh"
        return map
    }()
}

private final class DisplayLocationCache {
    static let shared = DisplayLocationCache()
    private var map: [UUID: String] = [:]
    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let prefix = "PlaceLocationCache:v2:"

    func get(placeID: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let val = map[placeID] { return val }
        let key = prefix + placeID.uuidString
        return defaults.string(forKey: key)
    }

    func set(placeID: UUID, value: String) {
        lock.lock(); map[placeID] = value; lock.unlock()
        let key = prefix + placeID.uuidString
        defaults.set(value, forKey: key)
    }
}

private extension String {
    func capitalizedWords() -> String {
        self.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
    func caseInsensitiveEquals(_ other: String) -> Bool { self.lowercased() == other.lowercased() }
}

// Thumbnail loader for Top Rated rows
private struct TopRatedPhotoThumb: View {
    let placeID: UUID
    @State private var imageURL: URL?
    @State private var attempted = false
    private static var urlCache: [UUID: URL] = [:]

    var body: some View {
        if let local = TopRatedPhotoThumb.localThumb(for: placeID) {
            Image(uiImage: local)
                .resizable()
                .scaledToFill()
        } else {
            let resolvedURL = imageURL ?? TopRatedPhotoThumb.urlCache[placeID]
            Group {
                if let url = resolvedURL {
                    CachedAsyncImage(url: url) {
                        Color.gray.opacity(0.3)
                    } failure: {
                        placeholder
                    }
                    .scaledToFill()
                } else {
                    placeholder
                }
            }
            .task(id: placeID) {
                guard !attempted else { return }
                attempted = true
                await loadThumbnailAndCuisine()
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.25)
            Text("🍔🥤")
                .font(.system(size: 24))
                .opacity(0.9)
        }
    }

    private struct PhotoRow: Decodable { let image_url: String }
    @MainActor
    private func loadThumbnailAndCuisine() async {
        do {
            // Build place_photo URL
            var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
            var p = comps.path
            if !p.hasSuffix("/") { p.append("/") }
            p.append("rest/v1/place_photo")
            comps.path = p
            comps.queryItems = [
                URLQueryItem(name: "place_id", value: "eq.\(placeID.uuidString)"),
                URLQueryItem(name: "order", value: "priority.asc"),
                URLQueryItem(name: "limit", value: "1")
            ]
            var req = URLRequest(url: comps.url!)
            let key = Env.anonKey
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let row = try? JSONDecoder().decode([PhotoRow].self, from: data).first,
                   let url = URL(string: row.image_url) {
                    imageURL = url
                    TopRatedPhotoThumb.urlCache[placeID] = url
                    // Prefetch the bitmap into cache for near-instant reuse
                    _ = try? await URLSession.shared.data(from: url).0
                }
            }
        } catch {
            // ignore failures silently
        }
    }

    // Check for a bundled asset named "thumb_<UUID>"
    private static func localThumb(for id: UUID) -> UIImage? {
        let name = "thumb_\(id.uuidString)"
        return UIImage(named: name)
    }

    // Allow prefetching from TopRatedScreen
    static func prefetch(for id: UUID) {
        if localThumb(for: id) != nil { return }
        if urlCache[id] != nil { return }
        Task.detached {
            do {
                var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
                var p = comps.path
                if !p.hasSuffix("/") { p.append("/") }
                p.append("rest/v1/place_photo")
                comps.path = p
                comps.queryItems = [
                    URLQueryItem(name: "place_id", value: "eq.\(id.uuidString)"),
                    URLQueryItem(name: "order", value: "priority.asc"),
                    URLQueryItem(name: "limit", value: "1")
                ]
                var req = URLRequest(url: comps.url!)
                let key = Env.anonKey
                req.setValue(key, forHTTPHeaderField: "apikey")
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                req.setValue("public", forHTTPHeaderField: "Accept-Profile")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let row = try? JSONDecoder().decode([PhotoRow].self, from: data).first,
                       let url = URL(string: row.image_url) {
                        urlCache[id] = url
                        // Fetch to populate image cache
                        _ = try? await URLSession.shared.data(from: url)
                    }
                }
            } catch { /* ignore */ }
        }
    }
}


private struct ZoomableCachedImage<Placeholder: View, Failure: View>: View {
    let url: URL
    let resetID: UUID
    let placeholder: Placeholder
    let failure: Failure

    @State private var uiImage: UIImage?

    init(url: URL, resetID: UUID, @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder failure: () -> Failure) {
        self.url = url
        self.resetID = resetID
        self.placeholder = placeholder()
        self.failure = failure()
    }

    var body: some View {
        Group {
            if let uiImage {
                ZoomableScrollView(resetID: resetID) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            } else {
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        if let cached = ImageCache.shared.image(for: url) {
            uiImage = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ImageCache.shared.store(image, for: url)
                uiImage = image
            }
        } catch {
            // noop; placeholder remains
        }
    }
}

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let resetID: UUID
    let content: Content

    init(resetID: UUID, @ViewBuilder content: () -> Content) {
        self.resetID = resetID
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, resetID: resetID)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.frame = scrollView.bounds
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(hostedView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        if context.coordinator.lastResetID != resetID {
            scrollView.setZoomScale(1, animated: false)
            scrollView.contentOffset = .zero
            context.coordinator.lastResetID = resetID
        }
        context.coordinator.centerContent(scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        var lastResetID: UUID

        init(content: Content, resetID: UUID) {
            hostingController = UIHostingController(rootView: content)
            hostingController.view.backgroundColor = .clear
            lastResetID = resetID
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
        }

        func centerContent(_ scrollView: UIScrollView) {
            guard let view = hostingController.view else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }
    }
}

// MARK: - Lightweight image + photo caches (scoped here to avoid Xcode project updates)

final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let ioQueue = DispatchQueue(label: "ImageCache.IO")
    private let folderURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        folderURL = caches.appendingPathComponent("hf-image-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        memory.countLimit = 512
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }
        let path = folderURL.appendingPathComponent(String(url.absoluteString.hashValue))
        if let data = try? Data(contentsOf: path), let img = UIImage(data: data) {
            memory.setObject(img, forKey: url as NSURL)
            return img
        }
        return nil
    }

    func store(_ image: UIImage, for url: URL) {
        memory.setObject(image, forKey: url as NSURL)
        let path = folderURL.appendingPathComponent(String(url.absoluteString.hashValue))
        ioQueue.async {
            if let data = image.jpegData(compressionQuality: 0.92) ?? image.pngData() {
                try? data.write(to: path, options: .atomic)
            }
        }
    }
}

struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
                    .task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.store(img, for: url)
                image = img
            }
        } catch {
            // ignore
        }
    }
}

actor PlacePhotoCache {
    static let shared = PlacePhotoCache()
    private var map: [UUID: [PlacePhoto]] = [:]
    func get(_ id: UUID) -> [PlacePhoto]? { map[id] }
    func set(_ id: UUID, photos: [PlacePhoto]) { map[id] = photos }
}

private struct FavoritesPanel: View {
    let favorites: [FavoritePlaceSnapshot]
    let sortOption: FavoritesSortOption
    let onSelect: (FavoritePlaceSnapshot) -> Void
    let onSortChange: (FavoritesSortOption) -> Void

    private let detailColor = Color.primary.opacity(0.65)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Favorites")
                    .font(.headline)
                if !favorites.isEmpty {
                    Text("\(favorites.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(detailColor)
                }
                Spacer()
            }

            if !favorites.isEmpty {
                HStack(spacing: 8) {
                    ForEach(FavoritesSortOption.allCases) { option in
                        sortButton(for: option)
                    }
                }
            }

            if favorites.isEmpty {
                Text("Tap the heart on a place to keep it handy here.")
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(favorites) { snapshot in
                            Button {
                                onSelect(snapshot)
                            } label: {
                                FavoriteRow(snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }

    private func sortButton(for option: FavoritesSortOption) -> some View {
        let isSelected = option == sortOption
        return Button {
            onSortChange(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : detailColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteRow: View {
    let snapshot: FavoritePlaceSnapshot

    private let detailColor = Color.primary.opacity(0.75)

    private var iconName: String {
        snapshot.category == .restaurant ? "fork.knife.circle.fill" : "mappin.circle.fill"
    }

    private var iconColor: Color {
        switch snapshot.halalStatus {
        case .only:
            return .green
        case .yes:
            return .orange
        case .unknown:
            return .gray
        case .no:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.name)
                    .font(.headline)

                if let address = snapshot.address, !address.isEmpty {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                }

                Text(snapshot.halalStatus.label.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(detailColor)

                if let rating = snapshot.rating {
                    let count = snapshot.ratingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("(\(count) \(ratingLabel))")
                        if let source = snapshot.source, !source.isEmpty {
                            Text("- \(readableSource(source))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                } else if let source = snapshot.source, !source.isEmpty {
                    Text(readableSource(source))
                        .font(.caption2)
                        .foregroundStyle(detailColor)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NewSpotsScreen: View {
    @EnvironmentObject private var favoritesStore: FavoritesStore
    let spots: [NewSpotEntry]
    let spotlight: NewSpotEntry?
    let topInset: CGFloat
    let onSelect: (Place) -> Void

    var body: some View {
        let spotlightEntry = spotlight
        // Exclude the hero (spotlight) from the list so the top row reflects the latest new spot
        let listEntries: [NewSpotEntry] = {
            if let hero = spotlightEntry {
                return spots.filter { $0.id != hero.id }
            }
            return spots
        }()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if listEntries.isEmpty {
                    ProgressView("Loading new trendy spots…")
                        .progressViewStyle(.circular)
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    NewSpotsCard(spots: listEntries, onSelect: onSelect)
                    if let hero = spotlightEntry {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Text("Restaurant Spotlight")
                                    .font(.headline.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color.primary)

                            NewSpotHero(entry: hero, onSelect: onSelect)
                            SpotlightSummary(entry: hero)
                        }
                    }
                }
            }
            .padding(.top, max(topInset - 16, 0))
            .padding(.bottom, 32)
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private struct NewSpotsCard: View {
        @EnvironmentObject private var favoritesStore: FavoritesStore
        let spots: [NewSpotEntry]
        let onSelect: (Place) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                    Text("New Trending Spots")
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Color.primary)

                ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                    if index != 0 {
                        Divider()
                        .background(Color.black.opacity(0.06))
                    }
                    NewSpotRow(entry: spot, onSelect: onSelect)
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 9)
        }
    }

    private struct NewSpotRow: View {
        @EnvironmentObject private var favoritesStore: FavoritesStore
        let entry: NewSpotEntry
        let onSelect: (Place) -> Void

        private var place: Place { entry.place }

        var body: some View {
            Button {
                onSelect(place)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    HStack(alignment: .top, spacing: 12) {
                        CachedAsyncImage(url: entry.imageURL) {
                            Color.gray.opacity(0.3)
                        } failure: {
                            Color.gray.opacity(0.3)
                        }
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(place.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            ratingView(for: place)

                            Text(categoryLine())
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Label(entry.displayLocation, systemImage: "mappin.and.ellipse")
                                .labelStyle(.titleAndIcon)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }

                        Spacer(minLength: 8)

                        FavoriteToggleSmall(place: place)
                    }
                    .padding(.vertical, 4)

                    DateOpenedLabel(month: entry.openedOn.month, day: entry.openedOn.day)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                }
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private func ratingView(for place: Place) -> some View {
            Group {
                if let rating = place.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                        Text(String(format: "%.1f", rating))
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                        Text("(\(reviewLabel(for: place.ratingCount)))")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }

        private func reviewLabel(for count: Int?) -> String {
            guard let count else { return "No reviews" }
            if count == 1 { return "1 review" }
            if count >= 1000 { return String(format: "%.1fk reviews", Double(count) / 1000.0) }
            return "\(count) reviews"
        }

        private func categoryLine() -> String {
            let status = entry.halalStatusOverride ?? place.halalStatus
            let halalLabel = status == .only ? "Fully halal" : status.label
            return "\(entry.cuisine) • \(halalLabel)"
        }
    }

    private struct FavoriteToggleSmall: View {
        @EnvironmentObject private var favoritesStore: FavoritesStore
        let place: Place

        private var isFavorite: Bool {
            favoritesStore.contains(id: place.id)
        }

        var body: some View {
            Button {
                favoritesStore.toggleFavorite(
                    for: place,
                    name: place.name,
                    address: place.address,
                    rating: place.rating,
                    ratingCount: place.ratingCount,
                    source: place.source,
                    applePlaceID: place.applePlaceID
                )
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }

    private struct NewSpotHero: View {
        let entry: NewSpotEntry
        let onSelect: (Place) -> Void

        var body: some View {
            Button {
                onSelect(entry.place)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: entry.imageURL) {
                        Color.gray.opacity(0.3)
                    } failure: {
                        Color.gray.opacity(0.3)
                    }
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.place.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text(entry.displayLocation)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.65), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    )
                    .overlay(alignment: .bottomTrailing) {
                        DateOpenedLabel(month: entry.openedOn.month, day: entry.openedOn.day)
                            .padding(.trailing, 32)
                            .padding(.bottom, 12)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private struct SpotlightSummary: View {
        let entry: NewSpotEntry

        private var hasContent: Bool {
            let texts = [entry.spotlightSummary, entry.spotlightBody, entry.spotlightDetails]
            return texts.contains { text in
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                return true
            }
        }

        var body: some View {
            Group {
                if hasContent {
                    VStack(alignment: .leading, spacing: 12) {
                        if let summary = entry.spotlightSummary {
                            Text(summary)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                        }
                        if let body = entry.spotlightBody {
                            Text(body)
                                .font(.body)
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .lineSpacing(4)
                        }
                        if let details = entry.spotlightDetails {
                            Text(details)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
                }
            }
        }
    }

    private struct DateOpenedLabel: View {
        let month: String
        let day: String

        var body: some View {
            CalendarBadge(month: month, day: day)
        }
    }

    private struct CalendarBadge: View {
        let month: String
        let day: String
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(spacing: 0) {
                Text(month.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 1)
                    .background(Color(UIColor.systemRed))
                Text(dayDisplay)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .background(Color(UIColor.secondarySystemBackground))
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }

        private var borderColor: Color {
            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.08)
        }

        private var dayDisplay: String {
            if let value = Int(day.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return String(value)
            }
            // Fallback to raw if parsing fails
            return day
        }
    }
}

struct PlaceDetailView: View {
    let place: Place

    @StateObject private var viewModel = PlaceDetailViewModel()
    @State private var expandedPhotoSelection: PhotoSelection?
    @State private var isRatingEmbeddedInAppleCard = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favoritesStore: FavoritesStore

    private var isFavorite: Bool {
        favoritesStore.isFavorite(place)
    }

    var body: some View {
        GeometryReader { proxy in
            let loadedDetails = appleLoadedDetails

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        if !viewModel.photos.isEmpty {
                            PhotoCarouselView(photos: viewModel.photos) { index, _ in
                                expandedPhotoSelection = PhotoSelection(index: index)
                            }
                        }
                        // Order: photos → halal details → rating (non-Apple path)
                        halalSection
                        if let ratingModel, !hasAppleDetails {
                            YelpRatingRow(model: ratingModel, style: .prominent)
                        }
                        Divider().opacity(0.4)
                        appleStatusSection
                    }
                    .padding(24)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .opacity(loadedDetails == nil ? 1 : 0)
                .allowsHitTesting(loadedDetails == nil)
                .overlay(alignment: .top) {
                    if let details = loadedDetails {
                        appleLoadedSection(details, availableHeight: proxy.size.height)
                    }
                }
            }
        }
        .fullScreenCover(item: $expandedPhotoSelection) { selection in
            FullscreenPhotoView(
                photos: viewModel.photos,
                initialIndex: selection.index
            ) {
                expandedPhotoSelection = nil
            }
        }
        .task(id: place.id) {
            await viewModel.load(place: place)
            await viewModel.loadPhotos(for: place)
            refreshFavoriteSnapshot()
        }
        .onReceive(viewModel.$loadingState) { _ in
            refreshFavoriteSnapshot()
        }
        .onReceive(viewModel.$photos) { photos in
            if let selection = expandedPhotoSelection,
               !photos.indices.contains(selection.index) {
                expandedPhotoSelection = nil
            }
        }
        .onChange(of: expandedPhotoSelection) { newValue in
            if let selection = newValue,
               !viewModel.photos.indices.contains(selection.index) {
                expandedPhotoSelection = nil
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.red : Color.white)
                .padding(6)
                .background(Color(.systemGray), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4.5, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func toggleFavorite() {
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            favoritesStore.toggleFavorite(
                for: place,
                name: displayName,
                address: displayAddress,
                rating: place.rating,
                ratingCount: place.ratingCount,
                source: place.source,
                applePlaceID: appleID
            )
        }
    }

    private func refreshFavoriteSnapshot() {
        guard favoritesStore.contains(id: place.id) else { return }
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        favoritesStore.updateFavoriteIfNeeded(
            for: place,
            name: displayName,
            address: displayAddress,
            rating: place.rating,
            ratingCount: place.ratingCount,
            source: place.source,
            applePlaceID: appleID
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                Spacer()
                if !hasAppleDetails {
                    favoriteButton
                }
            }

            if let address = displayAddress, !address.isEmpty {
                Label(address, systemImage: "mappin.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Rating moved below photos to follow: photos → rating → halal details.
        }
    }

    @ViewBuilder
    private var halalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            partialHalalMessageView()

            Label(place.halalStatus.label, systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Our halal classification comes from our own Supabase dataset.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appleStatusSection: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 12) {
                Label("Loading Apple Maps details…", systemImage: "apple.logo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView()
            }
            .frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Apple Maps unavailable", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("We never cache Apple Maps data. We'll retry the next time you open this place.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private func appleDetailsSection(_ details: ApplePlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let ratingModel {
                YelpRatingRow(model: ratingModel, style: .inline)
            }
            partialHalalMessageView()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Live from Apple Maps")
                        .font(.headline)
                    if let shortAddress = details.shortAddress {
                        Text(shortAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                favoriteButton
            }

            VStack(alignment: .leading, spacing: 10) {
                if let phone = details.phoneNumber {
                    let sanitized = viewModel.telephoneURLString(from: phone)
                    if let phoneURL = sanitized.isEmpty ? nil : URL(string: "tel://\(sanitized)") {
                        Button {
                            openURL(phoneURL)
                        } label: {
                            Label(phone, systemImage: "phone")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let website = details.websiteURL {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let category = details.pointOfInterestCategory {
                    Label(category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "tag")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let appleID = details.applePlaceID {
                    Text("Place ID: \(appleID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                viewModel.openInMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Apple Maps details are loaded live at runtime to stay within Apple's terms of use. Only the identifier is cached.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func applePlaceCard(_ details: ApplePlaceDetails) -> some View {
        MapItemDetailCardView(
            mapItem: details.mapItem,
            showsInlineMap: false,
            ratingModel: ratingModel,
            onRatingEmbedded: { embedded in
                if embedded != isRatingEmbeddedInAppleCard {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRatingEmbeddedInAppleCard = embedded
                        }
                    }
                }
            }
        ) {
            dismiss()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 11, y: 6)
        .overlay(alignment: .topTrailing) {
            favoriteButton
                .padding(.trailing, 15.5)
                .padding(.top, 58)
        }
    }

    @ViewBuilder
    private func appleLoadedSection(_ details: ApplePlaceDetails, availableHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            if !viewModel.photos.isEmpty {
                PhotoCarouselView(photos: viewModel.photos) { index, _ in
                    expandedPhotoSelection = PhotoSelection(index: index)
                }
            }
            if #available(iOS 18.0, *) {
                // Order: photos → halal details → rating → Apple place card
                partialHalalMessageView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                if let ratingModel, !isRatingEmbeddedInAppleCard {
                    YelpRatingRow(model: ratingModel, style: .prominent)
                        .padding(.horizontal, 16)
                }
                applePlaceCard(details)
            } else {
                appleDetailsSection(details)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(minHeight: availableHeight, alignment: .top)
    }

    private var displayName: String {
        if case let .loaded(details) = viewModel.loadingState, !details.displayName.isEmpty {
            return details.displayName
        }
        return place.name
    }

    private var ratingSourceLabel: String? {
        guard let raw = place.source?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "Yelp" }
        return readableSource(raw)
    }

    private var ratingModel: RatingDisplayModel? {
        guard let rating = place.rating, rating > 0 else { return nil }
        return RatingDisplayModel(
            rating: rating,
            reviewCount: place.ratingCount,
            source: ratingSourceLabel
        )
    }

    private var displayAddress: String? {
        if case let .loaded(details) = viewModel.loadingState {
            if let short = details.shortAddress, !short.isEmpty {
                return short
            }
            if let full = details.fullAddress, !full.isEmpty {
                return full
            }
        }
        return place.address
    }

    private var hasAppleDetails: Bool {
        if case .loaded = viewModel.loadingState { return true }
        return false
    }

    @ViewBuilder
    private func partialHalalMessageView() -> some View {
        if let display = halalDetailsDisplay {
            HalalDetailsCard(
                headline: "Halal Details",
                note: display.note,
                reminder: display.reminder,
                status: display.status
            )
            .transition(AnyTransition.opacity)
        }
    }

    private var halalDetailsDisplay: HalalDetailsDisplay? {
        // Show details card for both partial (yes) and fully halal (only)
        switch place.halalStatus {
        case .yes:
            let reminder = "Please always double check with restaurant."
            let trimmed = place.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return HalalDetailsDisplay(status: .partial, note: note, reminder: reminder)
        case .only:
            let reminder = "Please always double check with restaurant."
            let trimmed = place.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return HalalDetailsDisplay(status: .full, note: note, reminder: reminder)
        default:
            return nil
        }
    }

}

private enum HalalUIStatus { case full, partial }

private struct HalalDetailsDisplay {
    let status: HalalUIStatus
    let note: String?
    let reminder: String
}

private struct HalalDetailsCard: View {
    let headline: String
    let note: String?
    let reminder: String
    let status: HalalUIStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headline)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)

                HalalStatusBadge(status: status)
            }

            if let note {
                Text(note)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(reminder)
                .font(.system(.caption, design: .rounded).italic())
                .foregroundStyle(reminderColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color { Color.primary }
    private var reminderColor: Color { Color.secondary.opacity(0.9) }
    private var surfaceColor: Color { Color(.secondarySystemGroupedBackground) }
    private var outlineColor: Color { Color.black.opacity(0.06) }
    private var shadowColor: Color { Color.black.opacity(0.05) }
}

private struct HalalStatusBadge: View {
    let status: HalalUIStatus
    private var label: String { status == .full ? "HALAL" : "PARTIAL" }
    private var color: Color { status == .full ? Color.green : Color.orange }
    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

extension PlaceDetailView {
    private var appleLoadedDetails: ApplePlaceDetails? {
        if case let .loaded(details) = viewModel.loadingState {
            return details
        }
        return nil
    }
}

private struct PhotoSelection: Identifiable, Equatable {
    let id = UUID()
    let index: Int
}

private struct FullscreenPhotoView: View {
    let photos: [PlacePhoto]
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(photos: [PlacePhoto], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.onDismiss = onDismiss
        let clamped = photos.indices.contains(initialIndex) ? initialIndex : 0
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            Group {
                if photos.isEmpty {
                    emptyPlaceholder
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { pair in
                            let index = pair.offset
                            let photo = pair.element
                            Group {
                                if let url = URL(string: photo.imageUrl) {
                                    ZoomableCachedImage(url: url, resetID: photo.id) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                    } failure: {
                                        tilePlaceholder
                                    }
                                } else {
                                    tilePlaceholder
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .offset(y: dragOffset)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            }
            .padding()
            .accessibilityLabel("Close photo")
            .offset(y: dragOffset)
        }
        .overlay(alignment: .bottomTrailing) {
            if !photos.isEmpty {
                Text("Photos: Yelp")
                    .font(.caption2)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
                    .offset(y: dragOffset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded restaurant photo")
        .accessibilityAddTraits(.isModal)
        .gesture(dismissDragGesture)
        .onChange(of: photos.count) { _ in
            clampIndexIfNeeded()
        }
        .onAppear {
            clampIndexIfNeeded()
        }
    }

    private var backgroundOpacity: Double {
        let progress = min(max(dragOffset / 400, 0), 1)
        return Double(1 - (progress * 0.6))
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let threshold: CGFloat = 160
                if max(translation, predicted) > threshold {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func clampIndexIfNeeded() {
        if let last = photos.indices.last {
            currentIndex = min(currentIndex, last)
        } else {
            currentIndex = 0
            onDismiss()
        }
    }

    private var tilePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 64))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.7))
            Text("Photo unavailable")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}


private struct PhotoCarouselView: View {
    let photos: [PlacePhoto]
    let onPhotoSelected: (Int, PlacePhoto) -> Void

    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { pair in
                let index = pair.offset
                let photo = pair.element
                ZStack {
                    if let url = URL(string: photo.imageUrl) {
                        CachedAsyncImage(url: url) {
                            ZStack { Color.secondary.opacity(0.1); ProgressView() }
                        } failure: {
                            Color.secondary.opacity(0.1)
                        }
                        .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.1)
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .tag(index)
                .onTapGesture {
                    onPhotoSelected(index, photo)
                }
                .accessibilityAddTraits(.isButton)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: photos) { newValue in
            if let lastIndex = newValue.indices.last {
                selectedIndex = min(selectedIndex, lastIndex)
            } else {
                selectedIndex = 0
            }
        }
        .onAppear {
            if let lastIndex = photos.indices.last {
                selectedIndex = min(selectedIndex, lastIndex)
            } else {
                selectedIndex = 0
            }
        }
    }
}

private struct AppleMapItemSheet: View {
    let selection: ApplePlaceSelection
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                MapItemDetailCardView(
                    mapItem: selection.mapItem,
                    showsInlineMap: true,
                    ratingModel: nil,
                    onRatingEmbedded: nil,
                    onFinished: onDismiss
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                AppleFallbackDetailView(details: ApplePlaceDetails(mapItem: selection.mapItem))
            }
        }
    }
}

private struct ApplePlaceSelection: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
}

extension ApplePlaceSelection: Equatable {
    static func == (lhs: ApplePlaceSelection, rhs: ApplePlaceSelection) -> Bool {
        lhs.id == rhs.id
    }
}

private struct AppleFallbackDetailView: View {
    let details: ApplePlaceDetails
    @Environment(\.openURL) private var openURL

    var body: some View {
        let name = details.displayName.isEmpty ? "Apple Maps Place" : details.displayName

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let address = details.fullAddress ?? details.shortAddress {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let phone = details.phoneNumber,
                   let phoneURL = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Button {
                        openURL(phoneURL)
                    } label: {
                        Label(phone, systemImage: "phone")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let website = details.websiteURL {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Button {
                    details.mapItem.openInMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}

@MainActor
final class AppleHalalSearchService: ObservableObject {
    @Published private(set) var results: [MKMapItem] = []

    private var searchTask: Task<Void, Never>?
    private var lastRegion: MKCoordinateRegion?
    private let debounceNanoseconds: UInt64 = 500_000_000

    func search(in region: MKCoordinateRegion) {
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return }

        if let last = lastRegion, regionIsSimilar(lhs: last, rhs: region) {
            return
        }

        searchTask?.cancel()
        searchTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "halal restaurant"
            // Enforce NYC + Long Island region if limiting is enabled
            request.region = RegionGate.enforcedRegion(for: region)
            request.resultTypes = [.pointOfInterest]
            if #available(iOS 13.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
            }

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                await MainActor.run {
                    // Post-filter just in case MapKit returns items outside the requested region
                    self.results = response.mapItems.filter { item in
                        guard RegionGate.allows(mapItem: item) else { return false }
                        if let name = item.name, PlaceOverrides.isMarkedClosed(name: name) { return false }
                        return true
                    }
                    self.lastRegion = RegionGate.enforcedRegion(for: region)
                }
            } catch is CancellationError {
                // Ignore cancellations
            } catch {
#if DEBUG
                print("[AppleHalalSearchService] search failed: \(error)")
#endif
            }
        }
    }

    private func regionIsSimilar(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDiff = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDiff = abs(lhs.center.longitude - rhs.center.longitude)
        let latSpanDiff = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let lonSpanDiff = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        let threshold = 0.002
        return latDiff < threshold && lonDiff < threshold && latSpanDiff < threshold && lonSpanDiff < threshold
    }
}

@MainActor
final class PlaceDetailViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded(ApplePlaceDetails)
        case failed(String)
    }

    @Published private(set) var loadingState: LoadingState = .idle
    @Published var photos: [PlacePhoto] = []

    private let service: ApplePlaceDetailService
    private var lastSuccessfulPlaceID: UUID?

    init(service: ApplePlaceDetailService? = nil) {
        if let service {
            self.service = service
        } else {
            self.service = ApplePlaceDetailService.shared
        }
    }

    func load(place: Place) async {
        if case .loaded = loadingState,
           lastSuccessfulPlaceID == place.id {
            return
        }

        loadingState = .loading
        do {
            let details = try await service.details(for: place)
            loadingState = .loaded(details)
            lastSuccessfulPlaceID = place.id
        } catch is CancellationError {
            loadingState = .idle
            lastSuccessfulPlaceID = nil
        } catch let serviceError as ApplePlaceDetailServiceError {
            loadingState = .failed(serviceError.errorDescription ?? "Apple Maps couldn't load right now.")
            lastSuccessfulPlaceID = nil
        } catch {
            loadingState = .failed(error.localizedDescription)
            lastSuccessfulPlaceID = nil
        }
    }

    func openInMaps() {
        guard case .loaded(let details) = loadingState else { return }
#if os(iOS)
        details.mapItem.openInMaps()
#endif
    }

    func telephoneURLString(from rawValue: String) -> String {
        var digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("+0123456789")
        digits.removeAll { !allowed.contains($0) }
        if digits.first == "+" {
            let prefix = String(digits.prefix(1))
            let rest = String(digits.dropFirst().filter { $0.isNumber })
            return prefix + rest
        } else {
            return String(digits.filter { $0.isNumber })
        }
    }

    func loadPhotos(for place: Place) async {
        do {
            if let cached = await PlacePhotoCache.shared.get(place.id) {
                self.photos = cached
                return
            }
            var comps = URLComponents(url: Env.url, resolvingAgainstBaseURL: false)!
            var p = comps.path
            if !p.hasSuffix("/") { p.append("/") }
            p.append("rest/v1/place_photo")
            comps.path = p
            comps.queryItems = [
                URLQueryItem(name: "place_id", value: "eq.\(place.id.uuidString)"),
                URLQueryItem(name: "order", value: "priority.asc"),
                URLQueryItem(name: "limit", value: "12")
            ]
            guard let url = comps.url else { return }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let key = Env.anonKey
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let rows = try decoder.decode([PlacePhoto].self, from: data)
            self.photos = rows
            await PlacePhotoCache.shared.set(place.id, photos: rows)
        } catch {
            // ignore
        }
    }
}

@MainActor
final class MapScreenViewModel: @MainActor ObservableObject {
    @Published private(set) var places: [Place] = [] {
        didSet {
            guard oldValue != places else { return }
            filteredPlacesVersion = filteredPlacesVersion &+ 1
        }
    }
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var presentingError = false
    @Published private(set) var searchResults: [Place] = [] {
        didSet {
            guard oldValue != searchResults else { return }
            searchResultsVersion = searchResultsVersion &+ 1
        }
    }
    @Published private(set) var isSearching = false
    @Published private(set) var filteredPlacesVersion: Int = 0
    @Published private(set) var searchResultsVersion: Int = 0

    var subtitleMessage: String? {
        guard !isLoading else { return "We're looking for new halal spots." }
        guard !places.isEmpty else { return "Pan the map to explore more halal spots." }
        return nil
    }

    var errorDescription: String {
        guard let message = errorMessage, !presentingError else { return "" }
        return message
    }

    private var fetchTask: Task<Void, Never>?
    private var manualSearchTask: Task<Void, Never>?
    private var globalDatasetTask: Task<Void, Never>?
    private var remoteSearchTask: Task<Void, Never>?
    private var appleFallbackTask: Task<Void, Never>?
    private var localFilterComputationTask: Task<[Place], Error>?
    private var localFilterDeliveryTask: Task<Void, Never>?
    private var lastRequestedRegion: MKCoordinateRegion?
    private var cache = PlaceCache()
    private var allPlaces: [Place] = []
    private var globalDataset: [Place] = []
    private var lastSearchQuery: String?
    private var currentFilter: MapFilter = .all
    private var appleIngestTasks: [String: Task<Void, Never>] = [:]
    private var ingestedApplePlaceIDs: Set<String> = []
    private let diskCache = PlaceDiskCache()
    private var didAttemptDiskBootstrap = false
    private var persistTask: Task<Void, Never>?
    private var lastPersistedFingerprint: Int?
    private var pendingPersistFingerprint: Int?
    private let persistDebounceNanoseconds: UInt64 = 1_500_000_000
    private let diskSnapshotStalenessInterval: TimeInterval = 60 * 60 * 6

    func place(with id: UUID) -> Place? {
        if let match = places.first(where: { $0.id == id }) { return match }
        if let match = searchResults.first(where: { $0.id == id }) { return match }
        if let match = allPlaces.first(where: { $0.id == id }) { return match }
        if let match = globalDataset.first(where: { $0.id == id }) { return match }
        return nil
    }

    func initialLoad(region: MKCoordinateRegion, filter: MapFilter) {
        currentFilter = filter
        bootstrapFromDiskIfNeeded(region: region, filter: filter)
        guard allPlaces.isEmpty else {
            apply(filter: filter)
            return
        }
        fetch(region: region, filter: filter, eager: true)
    }

    func filterChanged(to filter: MapFilter, region: MKCoordinateRegion) {
        currentFilter = filter
        if allPlaces.isEmpty {
            fetch(region: region, filter: filter, eager: true)
        } else {
            apply(filter: filter)
        }
    }

    func regionDidChange(to region: MKCoordinateRegion, filter: MapFilter) {
        currentFilter = filter
        fetch(region: region, filter: filter, eager: false)
    }

    func forceRefresh(region: MKCoordinateRegion, filter: MapFilter) {
        lastRequestedRegion = nil
        fetch(region: region, filter: filter, eager: true)
    }

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteSearchTask?.cancel()
        remoteSearchTask = nil
        manualSearchTask?.cancel()
        manualSearchTask = nil
        appleFallbackTask?.cancel()
        appleFallbackTask = nil
        localFilterDeliveryTask?.cancel()
        localFilterDeliveryTask = nil
        localFilterComputationTask?.cancel()
        localFilterComputationTask = nil

        lastSearchQuery = trimmed

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            updateSearchActivityIndicator()
            return
        }

        ensureGlobalDataset()

        let localSnapshot = allPlaces
        let globalSnapshot = globalDataset

        isSearching = true
        searchResults = []

        let filterTask = Task.detached(priority: .userInitiated) { () throws -> [Place] in
            try Task.checkCancellation()
            return Self.combinedMatchesSnapshot(local: localSnapshot, global: globalSnapshot, query: trimmed)
        }
        localFilterComputationTask = filterTask

        localFilterDeliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.localFilterDeliveryTask = nil
                self.localFilterComputationTask = nil
                self.updateSearchActivityIndicator()
            }

            do {
                let matches = try await filterTask.value
                guard !Task.isCancelled else { return }
                guard self.lastSearchQuery == trimmed else { return }
                let merged = self.deduplicate(self.searchResults + matches)
                self.searchResults = PlaceOverrides.sorted(merged)
            } catch is CancellationError {
                return
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Local search filtering failed for query \(trimmed):", error)
#endif
            }
        }

        updateSearchActivityIndicator()

        remoteSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.remoteSearchTask = nil
                self.updateSearchActivityIndicator()
                self.triggerAppleFallbackIfNecessary(for: trimmed)
            }

            do {
                let dtos = try await PlaceAPI.searchPlaces(matching: trimmed, limit: 80)
                guard !Task.isCancelled else { return }
                let remotePlaces = dtos.compactMap(Place.init(dto:)).filteredByCurrentGeoScope()
                guard !remotePlaces.isEmpty else { return }

                let referenceCoordinate = remotePlaces.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                let region = MKCoordinateRegion(center: referenceCoordinate, span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0))
                let cleaned = PlaceOverrides
                    .apply(overridesTo: remotePlaces, in: region)
                    .filteredByCurrentGeoScope()
                    .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .filter(self.isTrustedPlace(_:))
                guard !cleaned.isEmpty else { return }
                self.mergeIntoGlobalDataset(cleaned)
                let merged = self.deduplicate(self.searchResults + cleaned)
                self.searchResults = PlaceOverrides.sorted(merged)
            } catch is CancellationError {
                // Ignore cancellations
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Remote search failed for query \(trimmed):", error)
#endif
            }
        }

        manualSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.manualSearchTask = nil
                self.updateSearchActivityIndicator()
            }
            let exclusion = self.searchResults + self.allPlaces + self.globalDataset
            let additionalManual = await ManualPlaceResolver
                .shared
                .searchMatches(for: trimmed, excluding: exclusion)
                .filteredByCurrentGeoScope()
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .filter(self.isTrustedPlace(_:))
            guard !Task.isCancelled else { return }
            guard !additionalManual.isEmpty else { return }
            self.mergeIntoGlobalDataset(additionalManual)
            let merged = self.deduplicate(self.searchResults + additionalManual)
            self.searchResults = PlaceOverrides.sorted(merged.filteredByCurrentGeoScope())
        }
    }

    private func fetch(region: MKCoordinateRegion, filter: MapFilter, eager: Bool) {
        let requestRegion = normalizedRegion(for: region)
        let cacheHit = cache.value(for: requestRegion)
        let cachedOverride = cacheHit.map {
            PlaceOverrides
                .apply(overridesTo: $0.places, in: requestRegion)
                .filter(self.isTrustedPlace(_:))
        }

        if let cachedPlaces = cachedOverride {
            // Show cached results immediately for snappy UI, but do not return early here.
            // We still evaluate whether to fetch fresh data based on region changes below.
            allPlaces = cachedPlaces
            apply(filter: filter)
            // Intentionally not returning on fresh cache; fetching decision happens below.
        }

        if let last = lastRequestedRegion,
           regionIsSimilar(lhs: last, rhs: requestRegion),
           !(cacheHit == nil || cacheHit?.isFresh == false || eager) {
            return
        }

        fetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        presentingError = false
        lastRequestedRegion = requestRegion

        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !eager {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            do {
                let dtos = try await Task.detached(priority: .userInitiated) {
                    try await PlaceAPI.getPlaces(bbox: requestRegion.bbox)
                }.value
                // Convert and enforce NYC + Long Island scope
                let results = dtos.compactMap(Place.init(dto:)).filteredByCurrentGeoScope()
                let overridden = PlaceOverrides.apply(overridesTo: results, in: requestRegion)
                let cleaned = overridden
                    .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .filter(self.isTrustedPlace(_:))
                // Only surface verified halal places by default
                let halalOnly = cleaned.filter { $0.halalStatus == .yes || $0.halalStatus == .only }

                // Bring in manual outliers (e.g., venues not tagged halal in OSM/Apple)
                // so they always appear on the map within the current region.
                // Always evaluate manual places across the broader NYC + Long Island scope
                // so outliers (e.g., LIC while viewing Manhattan) still appear on the map.
                let manual = await ManualPlaceResolver
                    .shared
                    .manualPlaces(in: Self.appleFallbackRegion, excluding: halalOnly)
                    .filteredByCurrentGeoScope()
                    .filter(self.isTrustedPlace(_:))

                try Task.checkCancellation()
                let combined = self.deduplicate(halalOnly + manual).filteredByCurrentGeoScope()
                let sanitizedCombined = combined.filter(self.isTrustedPlace(_:))
                self.allPlaces = PlaceOverrides.sorted(sanitizedCombined)
                self.mergeIntoGlobalDataset(sanitizedCombined, replacingSources: Set(["seed"]))
                self.apply(filter: self.currentFilter)
                self.isLoading = false
                self.cache.store(sanitizedCombined, region: requestRegion)
            } catch is CancellationError {
                // Swallow cancellation; any inflight request will manage loading state.
            } catch {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }
                self.errorMessage = Self.message(for: error)
                self.presentingError = true
                if self.places.isEmpty, let cachedPlaces = cachedOverride {
                    self.allPlaces = cachedPlaces
                        .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .filter(self.isTrustedPlace(_:))
                    self.apply(filter: self.currentFilter)
                }
                self.isLoading = false
            }
        }
    }

    private func bootstrapFromDiskIfNeeded(region: MKCoordinateRegion, filter: MapFilter) {
        guard !didAttemptDiskBootstrap else { return }
        didAttemptDiskBootstrap = true

        let seedRegion = normalizedRegion(for: region)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let snapshot = await self.diskCache.loadSnapshot(), !snapshot.places.isEmpty {
                let filtered = snapshot.places
                    .filteredByCurrentGeoScope()
                    .filter(self.isTrustedPlace(_:))
                guard !filtered.isEmpty else {
                    self.ensureGlobalDataset(forceRefresh: true)
                    return
                }
                self.mergeIntoGlobalDataset(filtered, persist: false)
                self.allPlaces = self.globalDataset
                self.apply(filter: filter)
                self.cache.store(self.allPlaces, region: seedRegion)
                self.lastPersistedFingerprint = self.persistenceFingerprint(for: self.globalDataset)
                await self.diskCache.saveSnapshot(places: self.globalDataset)

                let isStale = Date().timeIntervalSince(snapshot.savedAt) > self.diskSnapshotStalenessInterval
                if isStale {
                    self.ensureGlobalDataset(forceRefresh: true)
                }
            } else {
                let seeds = self.loadBundledSeedPlaces()
                if !seeds.isEmpty {
                    let filteredSeeds = seeds.filteredByCurrentGeoScope()
                    let sanitizedSeeds = filteredSeeds.filter(self.isTrustedPlace(_:))
                    if !sanitizedSeeds.isEmpty {
                        self.mergeIntoGlobalDataset(sanitizedSeeds, persist: false)
                        self.allPlaces = PlaceOverrides.sorted(sanitizedSeeds)
                        self.apply(filter: filter)
                        self.cache.store(sanitizedSeeds, region: seedRegion)
                    }
                }
                self.ensureGlobalDataset()
            }
        }
    }

    private func normalizedRegion(for region: MKCoordinateRegion) -> MKCoordinateRegion {
        let minDelta: CLLocationDegrees = 0.05
        let maxDelta: CLLocationDegrees = 4.5
        let multiplier: CLLocationDegrees = 1.35

        let baseLat = max(region.span.latitudeDelta, minDelta)
        let baseLon = max(region.span.longitudeDelta, minDelta)

        let latitudeDelta = min(baseLat * multiplier, maxDelta)
        let longitudeDelta = min(baseLon * multiplier, maxDelta)

        return MKCoordinateRegion(center: region.center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }

    private func schedulePersistGlobalDataset() {
        guard !globalDataset.isEmpty else { return }
        let fingerprint = persistenceFingerprint(for: globalDataset)
        if fingerprint == lastPersistedFingerprint || fingerprint == pendingPersistFingerprint {
            return
        }

        pendingPersistFingerprint = fingerprint
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingPersistFingerprint == fingerprint {
                    self.pendingPersistFingerprint = nil
                }
            }
            do {
                try await Task.sleep(nanoseconds: persistDebounceNanoseconds)
            } catch {
                return
            }
            let snapshot = self.globalDataset
            guard !snapshot.isEmpty else { return }
            await self.diskCache.saveSnapshot(places: snapshot)
            self.lastPersistedFingerprint = fingerprint
        }
    }

    private func persistenceFingerprint(for places: [Place]) -> Int {
        var hasher = Hasher()
        hasher.combine(places.count)
        for place in places {
            hasher.combine(place.id)
            hasher.combine(place.name)
            hasher.combine(place.halalStatus.rawValue)
            hasher.combine(place.rating ?? -1)
            hasher.combine(place.ratingCount ?? -1)
            hasher.combine(place.confidence ?? -1)
            hasher.combine(place.address ?? "")
            hasher.combine(place.source ?? "")
        }
        return hasher.finalize()
    }

    private func apply(filter: MapFilter) {
        let filtered: [Place]
        switch filter {
        case .all:
            filtered = allPlaces
        case .fullyHalal:
            filtered = allPlaces.filter { $0.halalStatus == .only }
        case .partialHalal:
            filtered = allPlaces.filter { $0.halalStatus == .yes }
        }
        places = filtered
    }

    fileprivate func communityTopRatedSnapshot() -> CommunityTopRatedSnapshot {
        return CommunityTopRatedSnapshot(
            allPlaces: allPlaces,
            globalPlaces: globalDataset,
            searchResults: searchResults,
            yelpFallback: topRatedPlaces(limit: 80, minimumReviews: 5)
        )
    }

    func topRatedPlaces(limit: Int = 50, minimumReviews: Int = 10) -> [Place] {
        let source: [Place]
        if !globalDataset.isEmpty {
            source = globalDataset
        } else {
            source = allPlaces
        }

        let candidates = source.filter { place in
            guard let rating = place.rating, rating > 0 else { return false }
            return (place.ratingCount ?? 0) >= minimumReviews
        }

        let sorted = candidates.sorted { lhs, rhs in
            switch (lhs.rating, rhs.rating) {
            case let (l?, r?) where l != r:
                return l > r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let lhsCount = lhs.ratingCount ?? 0
                let rhsCount = rhs.ratingCount ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        if sorted.count <= limit { return sorted }
        return Array(sorted.prefix(limit))
    }

    private func regionIsSimilar(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        let latDiff = abs(lhs.center.latitude - rhs.center.latitude)
        let lonDiff = abs(lhs.center.longitude - rhs.center.longitude)
        let latSpanDiff = abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta)
        let lonSpanDiff = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
        let threshold = 0.001
        return latDiff < threshold && lonDiff < threshold && latSpanDiff < threshold && lonSpanDiff < threshold
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? PlaceAPIError {
            switch apiError {
            case .invalidURL:
                return "The Supabase URL is misconfigured. Double-check the Info.plist entries."
            case .invalidResponse:
                return "Supabase returned an unexpected response."
            case let .server(statusCode, body):
                if statusCode == 401 || statusCode == 403 {
                    return "Supabase rejected the request. Make sure the anon key is correct and RLS allows access."
                }
                if let body, !body.isEmpty {
                    return "Supabase error (\(statusCode)): \(body)"
                }
                return "Supabase error (\(statusCode)). Try again later."
            }
        }
        if error is DecodingError {
            return "The place data was in an unexpected format."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return urlError.localizedDescription
            }
        }
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return "We couldn't reach Supabase right now. Pull to refresh or try again in a moment."
    }

    deinit {
        fetchTask?.cancel()
        manualSearchTask?.cancel()
        globalDatasetTask?.cancel()
        remoteSearchTask?.cancel()
        appleFallbackTask?.cancel()
        localFilterDeliveryTask?.cancel()
        localFilterComputationTask?.cancel()
        appleIngestTasks.values.forEach { $0.cancel() }
        persistTask?.cancel()
    }
}

private extension MapScreenViewModel {
    struct PlaceSeed: Decodable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let halalStatus: Place.HalalStatus

        func toPlace() -> Place {
            Place(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                halalStatus: halalStatus,
                source: "seed"
            )
        }
    }

    static let appleFallbackRegion: MKCoordinateRegion = {
        let center = CLLocationCoordinate2D(latitude: 40.789142, longitude: -73.13496)
        let span = MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.8)
        return MKCoordinateRegion(center: center, span: span)
    }()

    func ingestApplePlaceIfNeeded(_ mapItem: MKMapItem) {
        // Apple ingestion is disabled to avoid unvetted entries polluting the dataset.
        _ = mapItem
    }

    func triggerAppleFallbackIfNecessary(for query: String) {
        // Historically we fell back to Apple Maps to pad results, but that led to
        // non-database venues appearing as fully halal in search. Disable the
        // fallback entirely so we only surface places sourced from Supabase.
        return
    }

private static let nonHalalChainBlocklist: Set<String> = {
    let names = [
        "Subway", "Taco Bell", "McDonald's", "Burger King", "Wendy's",
        "KFC", "Chipotle", "Domino's", "Pizza Hut", "Papa John's",
        "Five Guys", "White Castle", "Panera Bread", "Starbucks",
        "Dunkin'", "Chick-fil-A", "Popeyes", "Arby's", "Jack in the Box",
        "Sonic Drive-In", "Little Caesars", "Carl's Jr", "Hardee's",
        "Little Ruby's", "Little Ruby's Cafe", "Little Ruby's SoHo"
    ]
    return Set(names.map { PlaceOverrides.normalizedName(for: $0) })
}()

    nonisolated static func isBlocklistedChainName(_ name: String) -> Bool {
        let normalized = PlaceOverrides.normalizedName(for: name)
        guard !normalized.isEmpty else { return false }
        for blocked in nonHalalChainBlocklist {
            if normalized.hasPrefix(blocked) { return true }
        }
        return false
    }

    nonisolated static func isBlocklistedChain(_ place: Place) -> Bool {
        isBlocklistedChainName(place.name)
    }

    private static func shouldIngestApplePlace(_ mapItem: MKMapItem) -> Bool {
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return false }
        if isBlocklistedChainName(name) { return false }
        return !PlaceOverrides.normalizedName(for: name).isEmpty
    }

    func combinedMatches(for query: String) -> [Place] {
        Self.combinedMatchesSnapshot(local: allPlaces, global: globalDataset, query: query)
    }

    func matches(in source: [Place], query: String) -> [Place] {
        let normalizedQuery = PlaceOverrides.normalizedName(for: query)
        return Self.matches(in: source, normalizedQuery: normalizedQuery)
    }

    nonisolated static func combinedMatchesSnapshot(local: [Place], global: [Place], query: String) -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalizedQuery = PlaceOverrides.normalizedName(for: trimmed)
        guard !normalizedQuery.isEmpty else { return [] }
        let localMatches = matches(in: local, normalizedQuery: normalizedQuery)
        let globalMatches = matches(in: global, normalizedQuery: normalizedQuery)
        return PlaceOverrides.deduplicate(localMatches + globalMatches)
    }

    nonisolated static func matches(in source: [Place], normalizedQuery: String) -> [Place] {
        guard !normalizedQuery.isEmpty else { return [] }

        return source.filter { place in
            guard !Self.isBlocklistedChain(place) else { return false }
            let trimmedName = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            let normalizedName = PlaceOverrides.normalizedName(for: place.name)
            if normalizedName.contains(normalizedQuery) { return true }

            if let address = place.address {
                let normalizedAddress = PlaceOverrides.normalizedName(for: address)
                if normalizedAddress.contains(normalizedQuery) { return true }
            }

            return false
        }
    }

    func ensureGlobalDataset(forceRefresh: Bool = false) {
        if forceRefresh {
            guard globalDatasetTask == nil else { return }
        } else {
            guard globalDataset.isEmpty, globalDatasetTask == nil else { return }
        }
        globalDatasetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let dtos = try await Task.detached(priority: .utility) {
                    try await PlaceAPI.fetchAllPlaces(limit: 3500)
                }.value
                let places = dtos
                    .compactMap(Place.init(dto:))
                    .filteredByCurrentGeoScope()
                    .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .filter(self.isTrustedPlace(_:))
                try Task.checkCancellation()
                self.mergeIntoGlobalDataset(places, replacingSources: Set(["seed"]))
                if let query = self.lastSearchQuery, !query.isEmpty {
                    let seeded = self.combinedMatches(for: query).filteredByCurrentGeoScope()
                    self.searchResults = PlaceOverrides.sorted(seeded)
                }
            } catch is CancellationError {
#if DEBUG
                print("[MapScreenViewModel] Global dataset fetch cancelled")
#endif
            } catch {
#if DEBUG
                print("[MapScreenViewModel] Failed to load global dataset:", error)
#endif
            }
            self.globalDatasetTask = nil
            self.updateSearchActivityIndicator()
        }
    }

    func mergeIntoGlobalDataset(_ newPlaces: [Place], replacingSources: Set<String> = [], persist: Bool = true) {
        guard !newPlaces.isEmpty else { return }
        let filtered = newPlaces
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter(isTrustedPlace)
        var sanitizedExisting = globalDataset.filter(isTrustedPlace)
        if !replacingSources.isEmpty {
            let needle = replacingSources.map { $0.lowercased() }
            sanitizedExisting.removeAll { place in
                guard let source = place.source?.lowercased(), !source.isEmpty else { return false }
                return needle.contains { source.contains($0) }
            }
        }
        guard !(filtered.isEmpty && sanitizedExisting == globalDataset) else { return }

        let combined = deduplicate(sanitizedExisting + filtered)
        let sorted = PlaceOverrides.sorted(combined)
        if sorted != globalDataset {
            globalDataset = sorted
        }

        let sanitizedAll = allPlaces.filter(isTrustedPlace)
        if sanitizedAll != allPlaces {
            allPlaces = sanitizedAll
            apply(filter: currentFilter)
        }

        let sanitizedSearch = searchResults.filter(isTrustedPlace)
        if sanitizedSearch != searchResults {
            searchResults = PlaceOverrides.sorted(sanitizedSearch)
        }

        if persist, !globalDataset.isEmpty {
            schedulePersistGlobalDataset()
        } else if persist, globalDataset.isEmpty {
            schedulePersistGlobalDataset()
        }
    }

    func loadBundledSeedPlaces() -> [Place] {
        guard let url = Bundle.main.url(forResource: "places_seed", withExtension: "json") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let seeds = try decoder.decode([PlaceSeed].self, from: data)
            return seeds.compactMap { $0.toPlace() }
        } catch {
#if DEBUG
            print("[MapScreenViewModel] Failed to load seed places:", error)
#endif
            return []
        }
    }

    func deduplicate(_ places: [Place]) -> [Place] {
        PlaceOverrides.deduplicate(places)
    }

    func insertOrUpdatePlace(_ place: Place) {
        guard isTrustedPlace(place) else { return }
        var updated = allPlaces
        if let existingIndex = updated.firstIndex(where: { $0.id == place.id }) {
            updated[existingIndex] = place
        } else {
            updated.append(place)
        }
        let deduped = deduplicate(updated)
        allPlaces = PlaceOverrides.sorted(deduped)
        apply(filter: currentFilter)
    }

    func refreshSearchResultsIfNeeded(with place: Place) {
        guard let query = lastSearchQuery, !query.isEmpty else { return }
        guard !matches(in: [place], query: query).isEmpty else { return }
        let deduped = deduplicate(searchResults + [place])
        searchResults = PlaceOverrides.sorted(deduped)
    }

    func updateSearchActivityIndicator() {
        let active = (remoteSearchTask != nil)
            || (manualSearchTask != nil)
            || (globalDatasetTask != nil)
            || (appleFallbackTask != nil)
            || (localFilterComputationTask != nil)
            || (localFilterDeliveryTask != nil)
        if active, let query = lastSearchQuery, !query.isEmpty {
            isSearching = true
        } else if !active {
            isSearching = false
        }
    }

    func makePlace(from mapItem: MKMapItem,
                   halalStatus: Place.HalalStatus,
                   confidence: Double?) -> Place? {
        let coordinate = mapItem.halalCoordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        let trimmedName = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else { return nil }

        return Place(
            name: trimmedName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: .restaurant,
            address: mapItem.halalShortAddress,
            halalStatus: halalStatus,
            rating: nil,
            ratingCount: nil,
            confidence: confidence,
            source: "apple",
            applePlaceID: mapItem.identifier?.rawValue
        )
    }
}

private struct PlaceCache {
    private struct Entry {
        let places: [Place]
        let timestamp: Date
    }

    private let ttl: TimeInterval
    private let staleCutoffMultiplier: Double = 3
    private var storage: [RegionCacheKey: Entry] = [:]

    init(ttl: TimeInterval = 600) {
        self.ttl = ttl
    }

    mutating func store(_ places: [Place], region: MKCoordinateRegion) {
        let key = RegionCacheKey(region: region)
        storage[key] = Entry(places: places, timestamp: Date())
    }

    mutating func value(for region: MKCoordinateRegion) -> (places: [Place], isFresh: Bool)? {
        let key = RegionCacheKey(region: region)
        guard let entry = storage[key] else { return nil }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > ttl * staleCutoffMultiplier {
            storage.removeValue(forKey: key)
            return nil
        }

        return (entry.places, age < ttl)
    }
}

private extension MapScreenViewModel {
    func isTrustedPlace(_ place: Place) -> Bool {
        if Self.isBlocklistedChain(place) { return false }
        guard let rawSource = place.source?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSource.isEmpty else {
            return true
        }
        let normalized = rawSource.lowercased()
        if normalized.contains("apple") {
            return normalized.hasPrefix("apple")
        }
        return true
    }
}

private struct RegionCacheKey: Hashable {
    let latBucket: Int
    let lonBucket: Int
    let latSpanBucket: Int
    let lonSpanBucket: Int

    init(region: MKCoordinateRegion) {
        latBucket = Self.bucket(for: region.center.latitude)
        lonBucket = Self.bucket(for: region.center.longitude)
        latSpanBucket = Self.bucket(for: region.span.latitudeDelta)
        lonSpanBucket = Self.bucket(for: region.span.longitudeDelta)
    }

    private static func bucket(for value: Double) -> Int {
        Int((value * 100).rounded())
    }
}

#Preview {
    ContentView()
}
