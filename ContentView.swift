import Combine
import CryptoKit
import Foundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import ImageIO

// MARK: - Blocked Google Photos
// Add photo ID fragments here to block outdated/inappropriate photos.
// Use the photo ID from the reference (the part after "/photos/").
private enum BlockedGooglePhotos {
    static let blockedPhotoIDs: Set<String> = [
        // King of Tandoor - 600 Flatbush Ave - outdated photo by Roni Khan
        "AcnlKN1KPW1RK9J8fREjV1y4M0yG88GymyjxzynC5_CkuKSraSlW558-LylUsuzPKUCHKjnWT1Dg0IYdbz6mpKmQrYS3klXtOk8ajK4hyjEziezuR9X2vloqAcl-soYhuaPOSt-myLqWts9HEpuv-t5QidTvdoLYTpHfXlduJEVnVV0ztk_YTD7OdiLuvqs2DMnQUv_SjhGWTC-BTl5SdUrzm_U0lKLTUnnmz2Gu8FTZFConPSV_3xql4wOtxazgYF9iNsjOxh3UBP6GTalgCYDIY8_GBRJYVqFbbHVPWsBrL7BxazXoacX3ID0WTh-JNw__m_74a9lTi5P1qHV4StVdq5MvURm5qsQLtBlbWx2bs5ErSyjx33B0AH57SvnFmGD4i1kdqmNIV0etNcMnv1QLhzIAKXcekQIQ-2sx8ApPjgnNww",
    ]

    static func isBlocked(url: String, reference: String?) -> Bool {
        blockedPhotoIDs.contains { id in
            url.contains(id) || (reference?.contains(id) ?? false)
        }
    }
}

enum MapFilter: CaseIterable, Identifiable {
    case all
    case fullyHalal
    case partialHalal
    case zabihahHalal

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .fullyHalal: return "Fully Halal"
        case .partialHalal: return "Partial Halal"
        case .zabihahHalal: return "Certified"
        }
    }

    var symbolName: String? {
        switch self {
        case .all: return nil
        case .fullyHalal: return "checkmark.seal.fill"
        case .partialHalal: return "circle.lefthalf.fill"
        case .zabihahHalal: return "checkmark.shield.fill"
        }
    }
}

private enum MapFilterBarItem: Identifiable {
    case filter(MapFilter)
    case category
    case cuisine

    var id: String {
        switch self {
        case .filter(let filter): return "filter-\(filter.id)"
        case .category: return "category"
        case .cuisine: return "cuisine"
        }
    }

    var title: String {
        switch self {
        case .filter(let filter): return filter.title
        case .category: return "Category"
        case .cuisine: return "Cuisine"
        }
    }

    var iconName: String? {
        switch self {
        case .filter(let filter): return filter.symbolName
        case .category: return "line.3.horizontal.decrease.circle"
        case .cuisine: return "fork.knife"
        }
    }
}

private enum MapFilterDropdown: Equatable {
    case category
    case cuisine
}

private enum CategoryFilterOption: String, CaseIterable, Identifiable {
    case cafe = "Cafe"
    case dessert = "Dessert"
    case foodTruck = "Food Truck"
    case grocery = "Grocery"
    case highEnd = "High-End"
    case new = "Newly Opened"

    var id: String { rawValue }
    var query: String {
        switch self {
        case .new: return "New"
        default: return rawValue
        }
    }
}

extension CategoryFilterOption: CustomStringConvertible {
    var description: String { rawValue }
}

private extension CategoryFilterOption {
    var categoryAliases: [String] {
        switch self {
        case .cafe:
            return ["coffee", "coffeeandtea", "cafes", "tea", "bubbletea", "juicebars"]
        case .dessert:
            return ["desserts", "icecream", "donuts", "bakeries", "cupcakes", "cakeshop", "chocolate", "gelato", "frozenyogurt", "macarons", "patisserie"]
        case .foodTruck:
            return ["foodtrucks", "streetvendors"]
        case .grocery:
            return ["grocery", "internationalgrocery", "meats", "butcher", "seafoodmarkets", "ethnicgrocery", "markets", "specialtyfood"]
        case .highEnd, .new:
            return []
        }
    }

    var fallbackNameTokens: [String] {
        switch self {
        case .cafe:
            return ["coffee", "cafe", "espresso", "latte", "tea"]
        case .dessert:
            return ["dessert", "bakery", "sweet", "cake", "icecream", "donut", "gelato"]
        case .foodTruck:
            return ["truck", "cart"]
        case .grocery:
            return ["market", "mart", "grocery", "bazaar", "butcher", "meat", "deli", "shop"]
        case .highEnd, .new:
            return []
        }
    }
}

private struct CategoryDropdownItem: Identifiable, CustomStringConvertible {
    let id: String
    let title: String
    let option: CategoryFilterOption?
    let isEnabled: Bool
    let statusText: String?

    var description: String { title }
}

private extension CategoryDropdownItem {
    static func active(_ option: CategoryFilterOption) -> CategoryDropdownItem {
        CategoryDropdownItem(
            id: option.rawValue,
            title: option.rawValue,
            option: option,
            isEnabled: true,
            statusText: nil
        )
    }

    static func disabled(_ option: CategoryFilterOption, statusText: String? = nil) -> CategoryDropdownItem {
        CategoryDropdownItem(
            id: option.rawValue,
            title: option.rawValue,
            option: option,
            isEnabled: false,
            statusText: statusText
        )
    }
}

private enum CuisineFilterOption: String, CaseIterable, Identifiable {
    case african = "African"
    case chinese = "Chinese"
    case italian = "Italian"
    case japanese = "Japanese"
    case mediterranean = "Mediterranean"
    case middleEastern = "Middle Eastern"
    case southAsian = "South Asian"
    case thai = "Thai"
    case turkish = "Turkish"

    var id: String { rawValue }
    var query: String { rawValue }
}

extension CuisineFilterOption: CustomStringConvertible {
    var description: String { rawValue }
}

private extension CuisineFilterOption {
    var categoryAliases: [String] {
        switch self {
        case .african:
            return ["african", "ethiopian", "eritrean", "egyptian", "moroccan", "senegalese", "somali", "nigerian", "sudanese"]
        case .chinese:
            return ["chinese", "cantonese", "szechuan", "shanghainese", "dimsum", "hunan", "taiwanese"]
        case .italian:
            return ["italian", "pizza", "pastashops"]
        case .japanese:
            return ["japanese", "sushi", "ramen", "izakaya", "tempura", "udon"]
        case .mediterranean:
            return ["mediterranean", "greek", "turkish", "tapas", "lebanese"]
        case .middleEastern:
            return ["middleeastern", "lebanese", "syrian", "arabian", "iranian", "persian", "iraqi", "egyptian", "moroccan", "afghani", "uzbek"]
        case .southAsian:
            return ["indpak", "indian", "pakistani", "bangladeshi", "srilankan", "himalayan", "nepalese", "bengali"]
        case .thai:
            return ["thai", "laotian"]
        case .turkish:
            return ["turkish", "ottoman"]
        }
    }

    var fallbackNameTokens: [String] {
        switch self {
        case .african:
            return ["african", "ethiopian", "eritrean", "egyptian", "moroccan", "nigerian", "somali", "sudanese"]
        case .chinese:
            return ["chinese", "szechuan", "hunan", "cantonese", "shanghai", "mandarin"]
        case .italian:
            return ["italian", "pizza", "pasta"]
        case .japanese:
            return ["japanese", "sushi", "ramen", "izakaya", "donburi"]
        case .mediterranean:
            return ["mediterranean", "greek", "mezze", "taverna"]
        case .middleEastern:
            return ["middleeastern", "lebanese", "syrian", "iraqi", "persian", "iranian", "moroccan", "egyptian", "afghan", "uzbek"]
        case .southAsian:
            return ["southasian", "indian", "pakistani", "bangladeshi", "desi", "srilankan", "nepali"]
        case .thai:
            return ["thai", "lao", "laotian"]
        case .turkish:
            return ["turkish", "anatolian", "ottoman"]
        }
    }
}

nonisolated private enum FavoritesSortOption: String, CaseIterable, Identifiable {
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

nonisolated private enum TopRatedSortOption: String, CaseIterable, Identifiable {
    case google
    case community

    var id: Self { self }

    var title: String {
        switch self {
        case .google: return "Top Rated"
        case .community: return "Community Ratings"
        }
    }
}

nonisolated private enum TopRatedRegion: String, CaseIterable, Identifiable {
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

nonisolated private enum CommunityTopRatedConfig {
    static let regions: [TopRatedRegion] = [.manhattan, .brooklyn, .queens, .bronx, .statenIsland, .longIsland]

    static let curatedNames: [TopRatedRegion: [String]] = [
        .manhattan: [
            "Top Thai",
            "Adel's",
            "Au Za'atar - Midtown East",
            "Nishaan",
            "Butter Smashburgers"
        ],
        .queens: [
            "Little Flower",
            "Darjeeling Kitchen & Cafe",
            "Zyara Restaurant",
            "Mahmoud's Corner",
            "Nur Thai"
        ],
        .brooklyn: [
            "BK Jani",
            "Milk & Honey Cafe",
            "Namkeen",
            "Ayat",
            "Affy's Premium Grill"
        ],
        .bronx: [
            "Waleed's Kitchen & Hot Wings",
            "Fry Chick",
            "Sooq NYC",
            "Halal Indian Grill",
            "Neerob Restaurant & Halal Chinese"
        ],
        .longIsland: [
            "Zaoq 100",
            "Rooh's BBQ Smoked Meat & Steakhouse",
            "Guac Time",
            "Halal Express Kabab House",
            "While in Kathmandu"
        ],
        .statenIsland: [
            "Kabab Time",
            "The Buttery"
        ]
    ]

    static let excludedFromAllLocations: Set<String> = Set([
        "Fry Chick",
        "Sooq NYC",
        "Halal Indian Grill",
        "Neerob Restaurant & Halal Chinese",
        "220 African Restaurant"
    ].map { PlaceOverrides.normalizedName(for: $0) })

}

#if DEBUG
@MainActor
final class CommunityInstrumentation: ObservableObject {
    private var loadSpan: PerformanceSpan?
    private var firstRenderLogged = false

    fileprivate func resetAll() {
        loadSpan = nil
        firstRenderLogged = false
    }

    fileprivate func resetFirstRender() {
        firstRenderLogged = false
    }

    fileprivate func startLoadIfNeeded(metadata: String) {
        guard loadSpan == nil else { return }
        loadSpan = PerformanceMetrics.begin(event: .communityFetch, metadata: metadata)
        firstRenderLogged = false
    }

    fileprivate func markWarmCache(region: TopRatedRegion, count: Int) {
        if loadSpan != nil {
            PerformanceMetrics.end(loadSpan, metadata: "Region switch with warm cache")
            loadSpan = nil
        }
        PerformanceMetrics.point(
            event: .communityDisplay,
            metadata: "Region \(region.rawValue) warm cache – \(count) places"
        )
        logFirstBatch(region: region, count: count)
    }

    fileprivate func markCancel(reason: String) {
        guard loadSpan != nil else { return }
        PerformanceMetrics.point(event: .communityFetch, metadata: reason)
        loadSpan = nil
        firstRenderLogged = false
    }

    fileprivate func markCachesPopulated(regionBucketCount: Int) {
        PerformanceMetrics.end(loadSpan, metadata: "Populated \(regionBucketCount) region caches")
        loadSpan = nil
    }

    fileprivate func logCacheHit(region: TopRatedRegion, count: Int) {
        guard !firstRenderLogged else { return }
        PerformanceMetrics.point(
            event: .communityDisplay,
            metadata: "Cache hit for \(region.rawValue) – \(count) places"
        )
        firstRenderLogged = true
    }

    fileprivate func logFirstBatch(region: TopRatedRegion, count: Int) {
        if !firstRenderLogged {
            PerformanceMetrics.point(
                event: .communityDisplay,
                metadata: "First batch ready for \(region.rawValue) – \(count) places"
            )
            firstRenderLogged = true
        } else {
            PerformanceMetrics.point(
                event: .communityDisplay,
                metadata: "Updated caches for \(region.rawValue) – \(count) places"
            )
        }
    }
}
#endif

private enum NewSpotImage: Equatable {
    case remote(URL)
    case asset(String)
}

private struct NewSpotConfig: Identifiable {
    let id = UUID()
    let placeID: UUID
    let image: NewSpotImage
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
        image: NewSpotImage,
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
        self.image = image
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
    let image: NewSpotImage
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
        image: NewSpotImage,
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
        self.image = image
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
    let googleFallback: [Place]
    let hasTrustedData: Bool
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

        let googleBase = snapshot.googleFallback
        var fallbackByRegion: [TopRatedRegion: [Place]] = [:]
        for region in CommunityTopRatedConfig.regions {
            let matches = googleBase.filter { CommunityRegionClassifier.matches($0, region: region) }
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
        var seen = Set<UUID>()
        let lists = CommunityTopRatedConfig.regions.compactMap { regionResults[$0] }
        let maxLen = lists.map { $0.count }.max() ?? 0
        if maxLen > 0 {
            for i in 0..<maxLen {
                for region in CommunityTopRatedConfig.regions {
                    if let list = regionResults[region], i < list.count {
                        let p = list[i]
                        let normalized = PlaceOverrides.normalizedName(for: p.name)
                        if CommunityTopRatedConfig.excludedFromAllLocations.contains(normalized) {
                            continue
                        }
                        if seen.insert(p.id).inserted {
                            combined.append(p)
                        }
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
        var seen = Set<UUID>()
        var result: [Place] = []
        result.reserveCapacity(places.count)
        for p in places { if seen.insert(p.id).inserted { result.append(p) } }
        return result
    }
}


struct ContentView: View {
    private static let appleDetailsEnabled = false

    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @AppStorage("hasLoadedPinsOnce") private var hasLoadedPinsOnce = false
    @State private var selectedFilter: MapFilter = .all
    @State private var bottomTab: BottomTab = .places
    @State private var selectedPlace: Place?
    @StateObject private var viewModel = MapScreenViewModel()
    @StateObject private var pinsStore = PlacePinsStore()
    @StateObject private var locationManager = LocationProvider()
    @StateObject private var appleHalalSearch = AppleHalalSearchService()
    @StateObject private var favoritesStore = FavoritesStore()
    @State private var favoritesSort: FavoritesSortOption = .recentlySaved
    @State private var topRatedSort: TopRatedSortOption = .google
    @State private var topRatedRegion: TopRatedRegion = .all
    @State private var hasCenteredOnUser = false
    @State private var selectedApplePlace: ApplePlaceSelection?
    @State private var searchQuery = ""
    @State private var isSearchOverlayPresented = false
    @State private var activeDropdown: MapFilterDropdown?
    @State private var selectedCategoryOption: CategoryFilterOption?
    @State private var selectedCuisineOption: CuisineFilterOption?
    @State private var keyboardHeight: CGFloat = 0
    @State private var previousMapRegion: MKCoordinateRegion?
    @State private var communityCache: [TopRatedRegion: [Place]] = [:]
    @State private var communityCacheIsStale = false
    @State private var communityPrecomputeTask: Task<Void, Never>?
    @State private var communityComputationGeneration: Int = 0
    @State private var visiblePlaces: [Place] = []
    @State private var refinedPlacesCache: [Place] = []
    @State private var refinedPlacesCacheVersion: Int = 0
    @State private var visiblePins: [PlacePin] = []
    @State private var viewportCache = ViewportCache()
    @State private var topRatedGoogleDataCache: [UUID: GooglePlaceData] = [:]
    @State private var topRatedGoogleOrderCache: [String: [UUID]] = [:]
    @State private var searchDebounceTask: DispatchWorkItem?
    @State private var pinSelectionTask: Task<Void, Never>?
    @State private var newSpotFetchTask: Task<Void, Never>?
    @State private var favoritesPanelTask: Task<Void, Never>?
    @State private var thumbnailPrefetchTask: Task<Void, Never>?
    @State private var filterSelectionVersion: Int = 0
    @State private var showInitialPinsLoader = false
    @State private var initialPinsProgress = 0.0
    @State private var isFavoritesPanelCollapsed = false
    @State private var isFavoritesPanelPinnedCollapsed = false
#if DEBUG
    @State private var didLogInitialAppear = false
    @StateObject private var communityInstrumentation = CommunityInstrumentation()
#endif

    private static let highEndTokens: Set<String> = {
        let candidates = [
            "au za'atar",
            "musaafer",
            "zaoq",
            "bungalow",
            "ishq"
        ]
        return Set(candidates.map { PlaceOverrides.normalizedName(for: $0) })
    }()
    private static let highEndPlaceIDs: Set<UUID> = [
        UUID(uuidString: "54322bf6-3346-48f3-8d84-cebcfe4cc103")!
    ]
    private let favoritesPanelAutoExpandNanoseconds: UInt64 = 650_000_000
    init() {
        let hasCachedPins = PlacePinsDiskCache.cachedSnapshotExists()
        let didLoadOnce = UserDefaults.standard.bool(forKey: "hasLoadedPinsOnce")
        let shouldShowInitial = !didLoadOnce && !hasCachedPins
        _showInitialPinsLoader = State(initialValue: shouldShowInitial)
        _initialPinsProgress = State(initialValue: shouldShowInitial ? 0.05 : 1.0)
    }

    private var topRatedGoogleOrderKey: String {
        "google:\(topRatedRegion.rawValue)"
    }

    private let newSpotConfigs: [NewSpotConfig] = [
        NewSpotConfig(
            placeID: UUID(uuidString: "a170b0ae-6b20-40f8-9660-26c45c3c4e83")!,
            image: .asset("FinalAppImage"),
            displayLocation: "Deer Park, Long Island",
            cuisine: "Mediterranean",
            halalStatusOverride: .only,
            openedOn: ("DEC", "28")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "95e9a6fd-6400-4e5b-934c-6443af9e118d")!,
            image: .asset("FinalAppImage"),
            displayLocation: "Jericho, Long Island",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("DEC", "23")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "04c36c10-efd7-4a9e-9ae5-e1871bbe6a13")!,
            image: .asset("FinalAppImage"),
            displayLocation: "Bethpage, Long Island",
            cuisine: "Chicken",
            halalStatusOverride: .only,
            openedOn: ("DEC", "06")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "71b2cf39-07d2-4e13-8b58-daf9952f3947")!,
            image: .asset("FinalAppImage"),
            displayLocation: "Hicksville, Long Island",
            cuisine: "Cafe",
            halalStatusOverride: .only,
            openedOn: ("OCT", "07")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "e35cfaee-b627-435a-9b38-3d3fc5d5fefa")!,
            image: .asset("FinalAppImage"),
            photoDescription: "MOTW Coffee signature latte",
            displayLocation: "Hicksville, Long Island",
            cuisine: "Coffee",
            halalStatusOverride: .only,
            openedOn: ("NOV", "01"),
            spotlightDetails: "Fully halal"
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "4cdda0c5-f0dd-4556-874f-628fa019d81b")!,
            image: .asset("FinalAppImage"),
            displayLocation: "Ronkonkoma, Long Island",
            cuisine: "Mexican",
            halalStatusOverride: .only,
            openedOn: ("OCT", "22")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "0384029a-69f2-4857-a289-36f44596cf36")!,
            image: .asset("FinalAppImage"),
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
            image: .asset("FinalAppImage"),
            photoDescription: "Prime No. 7 signature spread",
            displayLocation: "Astoria, Queens",
            cuisine: "Korean BBQ",
            halalStatusOverride: .only,
            openedOn: ("SEP", "12")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "06a506f7-e6e6-45f8-b5ed-00ffca921652")!,
            image: .asset("FinalAppImage"),
            photoDescription: "Sma.sha signature double smash",
            displayLocation: "Long Island City, Queens",
            cuisine: "Burgers",
            halalStatusOverride: nil,
            openedOn: ("SEP", "13"),
            spotlightSummary: "LIC’s newest burger lab focused on halal smashburgers and seasonal specials.",
            spotlightDetails: "All beef is halal; limited seating, take-out friendly."
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "f2e7df0e-d0e9-4f21-b398-f8768639503c")!,
            image: .asset("FinalAppImage"),
            photoDescription: "Flippin Buns smash classics",
            displayLocation: "Hicksville, Long Island",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("OCT", "18")
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "5765d9f5-527d-400a-b13d-6a63fbe6d707")!,
            image: .asset("FinalAppImage"),
            photoDescription: "Steiny B’s halal smashburger spread",
            displayLocation: "Flatbush, Brooklyn",
            cuisine: "Burgers",
            halalStatusOverride: .only,
            openedOn: ("AUG", "02"),
            spotlightSummary: "Flatbush smash shop named after the cheeseburger’s inventor, serving halal beef patties and Nashville hot chicken.",
            spotlightDetails: "Halal beef confirmed; small counter-service spot perfect for takeout."
        ),
        NewSpotConfig(
            placeID: UUID(uuidString: "bbe55fa0-3367-4624-8b5a-e45832395b63")!,
            image: .asset("FinalAppImage"),
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
                image: config.image,
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

    private var newSpotPlaces: [Place] {
        featuredNewSpots.map(\.place)
    }

    private var spotlightEntry: NewSpotEntry? {
        newSpotEntries.first(where: { $0.id == UUID(uuidString: "0384029a-69f2-4857-a289-36f44596cf36") }) ?? newSpotEntries.first
    }

    private var featuredNewSpots: [NewSpotEntry] {
        // Strict newest → oldest ordering for the list, independent of spotlight.
        newSpotEntries.sorted { lhs, rhs in
            sortValue(for: lhs) > sortValue(for: rhs)
        }
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

    private func preloadNewSpotDetailsIfNeeded() {
        guard newSpotFetchTask == nil else { return }
        var seen = Set<UUID>()
        let missingIDs = newSpotConfigs.compactMap { config -> UUID? in
            let id = config.placeID
            if let place = viewModel.place(with: id), place.hasGooglePlaceID {
                return nil
            }
            guard seen.insert(id).inserted else { return nil }
            return id
        }
        guard !missingIDs.isEmpty else { return }

        newSpotFetchTask = Task {
            do {
                let dtos = try await PlaceAPI.fetchPlaceDetailsByIDs(missingIDs)
                let places = dtos.compactMap(Place.init(dto:))
                await MainActor.run {
                    if !places.isEmpty {
                        viewModel.mergeIntoGlobalDataset(places, persist: false)
                    }
                    newSpotFetchTask = nil
                }
            } catch {
                await MainActor.run {
                    newSpotFetchTask = nil
                }
            }
        }
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
            servesAlcohol: place.servesAlcohol,
            source: place.source,
            sourceID: place.sourceID,
            externalID: place.externalID,
            googlePlaceID: place.googlePlaceID,
            googleMapsURL: place.googleMapsURL,
            applePlaceID: place.applePlaceID,
            note: place.note,
            displayLocation: place.displayLocation,
            categories: place.categories
        )
    }

    private func applyingOverrides(to places: [Place]) -> [Place] {
        places.map { applyingOverrides(to: $0) }
    }

    private func matchesCategory(_ place: Place, option: CategoryFilterOption) -> Bool {
        guard option != .highEnd, option != .new else { return false }
        if place.hasAnyCategory(option.categoryAliases) { return true }
        if normalizedMatches(place.name, tokens: option.fallbackNameTokens) { return true }
        if normalizedMatches(place.note, tokens: option.fallbackNameTokens) { return true }
        return false
    }

    private func matchesCuisine(_ place: Place, option: CuisineFilterOption) -> Bool {
        if place.hasAnyCategory(option.categoryAliases) { return true }
        if normalizedMatches(place.name, tokens: option.fallbackNameTokens) { return true }
        if normalizedMatches(place.note, tokens: option.fallbackNameTokens) { return true }
        return false
    }

    private func normalizedMatches(_ text: String?, tokens: [String]) -> Bool {
        guard let text, !text.isEmpty, !tokens.isEmpty else { return false }
        let normalized = PlaceOverrides.normalizedName(for: text)
        guard !normalized.isEmpty else { return false }
        for token in tokens {
            if normalized.contains(token) { return true }
        }
        return false
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

    private var isRefinedFilterActive: Bool {
        selectedCategoryOption != nil || selectedCuisineOption != nil || selectedFilter == .zabihahHalal
    }

    private var filterSelectionSignature: Int {
        var hasher = Hasher()
        hasher.combine(selectedCategoryOption?.rawValue ?? "")
        hasher.combine(selectedCuisineOption?.rawValue ?? "")
        return hasher.finalize()
    }

    private var filteredPlaces: [Place] {
        let usingRefinedDataset = isRefinedFilterActive
        let baseDataset: [Place]
        if usingRefinedDataset {
            viewModel.ensureGlobalDataset()
            baseDataset = viewModel.datasetForRefinedFilters()
        } else {
            baseDataset = viewModel.places
        }
        let scoped = baseDataset.filteredByCurrentGeoScope()

        if selectedCategoryOption == .highEnd {
            viewModel.ensureGlobalDataset()
            let fromViewModel = viewModel.curatedPlaces(matching: ContentView.highEndTokens)
            let curatedByID = ContentView.highEndPlaceIDs.compactMap { viewModel.place(with: $0) }
            let scopedByID = curatedByID.filteredByCurrentGeoScope()
            let curatedCombined = PlaceOverrides.deduplicate(fromViewModel + scopedByID)
            if !curatedCombined.isEmpty {
                return PlaceOverrides.sorted(curatedCombined)
            }
            let filtered: [Place]
            if fromViewModel.isEmpty {
                filtered = scoped.filter { place in
                    let normalized = PlaceOverrides.normalizedName(for: place.name)
                    return ContentView.highEndTokens.contains { token in
                        normalized.contains(token)
                    }
                }
            } else {
                filtered = fromViewModel
            }
            let fallbackByID = scoped.filter { ContentView.highEndPlaceIDs.contains($0.id) }
            return PlaceOverrides.deduplicate(filtered + fallbackByID)
        }

        if selectedCategoryOption == .new {
            viewModel.ensureGlobalDataset()
            let featured = newSpotPlaces
            return featured
        }

        if let category = selectedCategoryOption {
            let filtered = scoped.filter { matchesCategory($0, option: category) }
            return filtered
        }

        if let cuisine = selectedCuisineOption {
            let filtered = scoped.filter { matchesCuisine($0, option: cuisine) }
            return filtered
        }

        if selectedFilter == .zabihahHalal {
            let filtered = scoped.filter { $0.certifierOrg != nil }
            return filtered
        }

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return scoped }

        let matches = viewModel.searchResults.filteredByCurrentGeoScope()
        if matches.isEmpty, viewModel.isSearching {
            return scoped
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
        case .google:
            return viewModel.googleCandidatePlaces(limit: 60, region: topRatedRegion)
        case .community:
            return communityTopRated(for: topRatedRegion)
        }
    }

    private func communityTopRated(for region: TopRatedRegion) -> [Place] {
        if let cached = communityCache[region] {
#if DEBUG
            communityInstrumentation.logCacheHit(region: region, count: cached.count)
#endif
            return ensureUniqueIDs(cached)
        }
#if DEBUG
        if bottomTab == .topRated,
           topRatedSort == .community {
            communityInstrumentation.logCacheHit(region: region, count: 0)
        }
        #endif
        if communityPrecomputeTask == nil {
            let snapshot = viewModel.communityTopRatedSnapshot()
            if !snapshot.hasTrustedData {
                viewModel.ensureGlobalDataset(forceRefresh: true)
            }
            scheduleCommunityPrecomputationIfNeeded(force: true)
        }
        return []
    }

    private func resetCommunityCaches() {
        communityComputationGeneration &+= 1
        communityPrecomputeTask?.cancel()
        communityPrecomputeTask = nil
        if communityCache.isEmpty {
            communityCacheIsStale = false
        } else {
            communityCacheIsStale = true
        }
#if DEBUG
        communityInstrumentation.resetAll()
#endif
    }

    private func ensureUniqueIDs(_ places: [Place]) -> [Place] {
        var seen = Set<UUID>()
        var result: [Place] = []
        result.reserveCapacity(places.count)
        for p in places { if seen.insert(p.id).inserted { result.append(p) } }
        return result
    }

    private func scheduleCommunityPrecomputationIfNeeded(force: Bool = false) {
        if !force {
            if let cachedAll = communityCache[.all], !cachedAll.isEmpty, !communityCacheIsStale {
                return
            }
            if communityPrecomputeTask != nil {
                return
            }
        } else if !communityCache.isEmpty {
            communityCacheIsStale = true
        }

        communityPrecomputeTask?.cancel()
        communityPrecomputeTask = nil
        let snapshot = viewModel.communityTopRatedSnapshot()
        communityComputationGeneration &+= 1
        let generation = communityComputationGeneration
        if !communityCache.isEmpty {
            communityCacheIsStale = true
        }

        let hasSupabaseConfig = Env.optionalURL() != nil && Env.optionalAnonKey() != nil
        if !hasSupabaseConfig {
            if snapshot.hasTrustedData {
                let fallback = CommunityTopRatedEngine.compute(snapshot: snapshot)
                applyCommunityComputation(fallback, persist: false)
                communityCacheIsStale = false
            } else {
                communityCache[.all] = []
                communityCacheIsStale = false
            }
            communityPrecomputeTask = nil
            return
        }

#if DEBUG
        if bottomTab == .topRated,
           topRatedSort == .community {
            let metadata = force ? "Server fetch(force)" : "Server fetch"
            communityInstrumentation.startLoadIfNeeded(metadata: metadata)
        }
#endif

        communityPrecomputeTask = Task(priority: .utility) {
#if DEBUG
            let metadata = force ? "Fetch(force) gen=\(generation)" : "Fetch gen=\(generation)"
            let computeSpan = PerformanceMetrics.begin(
                event: .communityFetch,
                metadata: metadata
            )
#endif
            do {
                if snapshot.hasTrustedData {
                    let localResult = CommunityTopRatedEngine.compute(snapshot: snapshot)
                    await MainActor.run {
                        guard communityComputationGeneration == generation else { return }
                        let shouldHydrate = communityCacheIsStale || communityCache.isEmpty
                        if shouldHydrate {
                            applyCommunityComputation(localResult, persist: false)
                        }
                    }
                }

                let serverResults = try await MapScreenViewModel.fetchCommunityTopRated(limitPerRegion: 25)
                try Task.checkCancellation()
#if DEBUG
                PerformanceMetrics.end(
                    computeSpan,
                    metadata: "Server community results regions=\(serverResults.count)"
                )
#endif
                let mergedPlaces = serverResults.flatMap { $0.value }
                let updatedSnapshot = await MainActor.run { () -> CommunityTopRatedSnapshot? in
                    guard communityComputationGeneration == generation else { return nil }
                    if !mergedPlaces.isEmpty {
                        viewModel.mergeIntoGlobalDataset(mergedPlaces, persist: false)
                    }
                    return viewModel.communityTopRatedSnapshot()
                }
                guard let updatedSnapshot else { return }
                let curated = CommunityTopRatedEngine.compute(snapshot: updatedSnapshot)
                await MainActor.run {
                    guard communityComputationGeneration == generation else { return }
                    applyCommunityComputation(curated)
                    communityPrecomputeTask = nil
                }
            } catch is CancellationError {
#if DEBUG
                PerformanceMetrics.end(computeSpan, metadata: "cancelled")
#endif
                if communityComputationGeneration == generation {
                    communityPrecomputeTask = nil
                }
            } catch {
#if DEBUG
                PerformanceMetrics.point(
                    event: .communityFetch,
                    metadata: "Server community fetch failed – \(error.localizedDescription)"
                )
#endif
                if Task.isCancelled {
                    communityPrecomputeTask = nil
                    return
                }
                if snapshot.hasTrustedData {
                    let fallback = CommunityTopRatedEngine.compute(snapshot: snapshot)
#if DEBUG
                    PerformanceMetrics.point(
                        event: .communityFetch,
                        metadata: "Fallback local compute regions=\(fallback.regionResults.count)"
                    )
                    PerformanceMetrics.end(
                        computeSpan,
                        metadata: "fallback-success regions=\(fallback.regionResults.count)"
                    )
#endif
                    guard communityComputationGeneration == generation else { return }
                    applyCommunityComputation(fallback)
                    communityPrecomputeTask = nil
                } else {
#if DEBUG
                    PerformanceMetrics.end(computeSpan, metadata: "fallback-unavailable")
#endif
                    if communityComputationGeneration == generation {
                        communityPrecomputeTask = nil
                        viewModel.ensureGlobalDataset(forceRefresh: true)
                    }
                }
            }
        }
    }

    private func applyCommunityComputation(_ result: CommunityComputationResult, persist: Bool = true) {
        for (region, list) in result.regionResults {
            communityCache[region] = list
        }
        if persist {
            viewModel.persistCommunityTopRated(result.regionResults)
        }
#if DEBUG
        if persist {
            communityInstrumentation.markCachesPopulated(regionBucketCount: result.regionResults.count)
            let currentRegionCount = communityCache[topRatedRegion]?.count ?? communityCache[.all]?.count ?? 0
            communityInstrumentation.logFirstBatch(region: topRatedRegion, count: currentRegionCount)
        }
#endif
        if persist {
            communityCacheIsStale = false
        }
    }

    private var mapPlaces: [Place] {
        switch bottomTab {
        case .favorites:
            return applyingOverrides(to: favoritesDisplay.map { resolvedPlace(for: $0) })
        case .topRated:
            return applyingOverrides(to: topRatedDisplay)
        case .more:
            return []
        default:
            return applyingOverrides(to: visiblePlaces)
        }
    }

    private var mapPins: [PlacePin] {
        switch bottomTab {
        case .favorites, .topRated, .newSpots:
            return mapPlaces.map(PlacePin.init(place:))
        case .more:
            return []
        default:
            if isRefinedFilterActive {
                if shouldFetchDetails(for: mapRegion) {
                    return []
                }
                return mapPlaces.map(PlacePin.init(place:))
            }
            return visiblePins
        }
    }

    private var mapAppleItems: [MKMapItem] {
        switch bottomTab {
        case .favorites, .topRated:
            return []
        case .more:
            return []
        default:
            return appleOverlayItems
        }
    }

    private var isUserOutsideCoverage: Bool {
        guard let location = locationManager.lastKnownLocation else { return false }
        let coord = location.coordinate
        return !RegionGate.allows(lat: coord.latitude, lon: coord.longitude)
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
        applyPostOverlayModifiers(
            applyOverlayAndSheetModifiers(
                applyPreOverlayModifiers(baseContentView)
            )
        )
        .animation(.easeInOut(duration: 0.2), value: isSearchOverlayPresented)
    }

    @ViewBuilder
    private var baseContentView: some View {
        ZStack {
            if showInitialPinsLoader {
                InitialPinsLoadingView(
                    progress: initialPinsProgress,
                    isRefreshing: pinsStore.isRefreshing,
                    errorMessage: pinsStore.lastError,
                    onRetry: {
                        initialPinsProgress = 0.12
                        withAnimation(.linear(duration: 6.0)) {
                            initialPinsProgress = 0.9
                        }
                        pinsStore.refresh()
                    },
                    onContinue: {
                        hasLoadedPinsOnce = true
                        showInitialPinsLoader = false
                    }
                )
                .transition(.opacity)
            } else {
                mapShell
            }
        }
    }

    private func applyPreOverlayModifiers<V: View>(_ view: V) -> some View {
        let withAppear = applyAppearModifiers(view)
        let withChanges = applyChangeTrackingModifiers(withAppear)
        let withReceives = applyReceiveModifiers(withChanges)
        return applySearchAndAlertModifiers(withReceives)
    }

    private func applyAppearModifiers<V: View>(_ view: V) -> some View {
        view.onAppear {
            if !hasLoadedPinsOnce,
               pinsStore.didLoadFromDisk,
               pinsStore.pins.isEmpty,
               !showInitialPinsLoader {
                showInitialPinsLoader = true
                initialPinsProgress = 0.05
            }
            startInitialPinsLoaderIfNeeded()
            DispatchQueue.main.async {
                viewModel.initialLoad(region: mapRegion, filter: selectedFilter)
                // Pins are the fastest "time to usefulness" on first launch.
                pinsStore.refreshIfNeeded()
                preloadNewSpotDetailsIfNeeded()
                // Defer the full global dataset fetch so it doesn't compete with initial pins load.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    viewModel.ensureGlobalDataset()
                }
                locationManager.requestAuthorizationIfNeeded()
                if let existingLocation = locationManager.lastKnownLocation {
                    centerMap(on: existingLocation, markCentered: false)
                }
                locationManager.requestCurrentLocation()
                let effective = RegionGate.enforcedRegion(for: mapRegion)
                appleHalalSearch.search(in: effective)
                refreshVisiblePlaces()
                refreshVisiblePins()
                scheduleCommunityPrecomputationIfNeeded()
#if DEBUG
                if !didLogInitialAppear {
                    AppPerformanceTracker.shared.end(.appLaunch, metadata: "ContentView onAppear")
                    didLogInitialAppear = true
                }
#endif
            }
        }
    }

    private func applyChangeTrackingModifiers<V: View>(_ view: V) -> some View {
        applyDataChangeModifiers(applySelectionChangeModifiers(view))
    }

    private func applySelectionChangeModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: selectedFilter) { oldValue, newValue in
                guard oldValue != newValue else { return }
                viewModel.filterChanged(to: newValue, region: mapRegion)
                refreshVisiblePins()
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
    }

    private func applyDataChangeModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: viewModel.filteredPlacesVersion) { _, _ in
                resetCommunityCaches()
                if bottomTab == .topRated && topRatedSort == .community {
                    scheduleCommunityPrecomputationIfNeeded(force: true)
                }
                guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard bottomTab == .places || bottomTab == .newSpots else { return }
                refreshVisiblePlaces()
            }
            .onChange(of: viewModel.searchResultsVersion) { _, _ in
                guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard bottomTab == .places || bottomTab == .newSpots else { return }
                refreshVisiblePlaces()
            }
            .onChange(of: pinsStore.didLoadFromDisk) { _, didLoad in
                guard didLoad else { return }
                guard pinsStore.pins.isEmpty else { return }
                guard !hasLoadedPinsOnce else { return }
                if !showInitialPinsLoader {
                    showInitialPinsLoader = true
                    initialPinsProgress = 0.05
                }
                startInitialPinsLoaderIfNeeded()
            }
            .onChange(of: pinsStore.pins) { _, _ in
                if showInitialPinsLoader, !pinsStore.pins.isEmpty {
                    hasLoadedPinsOnce = true
                    completeInitialPinsLoader()
                } else if !hasLoadedPinsOnce, !pinsStore.pins.isEmpty {
                    hasLoadedPinsOnce = true
                }
                guard bottomTab == .places || bottomTab == .newSpots else { return }
                refreshVisiblePins()
            }
            .onChange(of: viewModel.globalDatasetVersion) { _, _ in
                guard bottomTab == .places || bottomTab == .newSpots else { return }
                guard selectedCategoryOption != nil || selectedCuisineOption != nil else { return }
                refreshVisiblePlaces()
            }
            .onChange(of: bottomTab) { _, newValue in
                if newValue != .favorites {
                    favoritesPanelTask?.cancel()
                    favoritesPanelTask = nil
                    if isFavoritesPanelCollapsed {
                        isFavoritesPanelCollapsed = false
                    }
                    if isFavoritesPanelPinnedCollapsed {
                        isFavoritesPanelPinnedCollapsed = false
                    }
                }
            }
    }

    private func applyReceiveModifiers<V: View>(_ view: V) -> some View {
        applyKeyboardReceiveModifiers(
            applyCommunityReceiveModifiers(
                applyLocationReceiveModifiers(view)
            )
        )
    }

    private func applyLocationReceiveModifiers<V: View>(_ view: V) -> some View {
        view.onReceive(locationManager.$lastKnownLocation.compactMap { $0 }) { location in
            guard !hasCenteredOnUser else { return }
            centerMap(on: location)
        }
    }

    private func applyCommunityReceiveModifiers<V: View>(_ view: V) -> some View {
        view.onReceive(viewModel.$persistedCommunityTopRated) { snapshot in
            guard !snapshot.isEmpty else { return }
            var merged = communityCache
            var didUpdate = false
            if merged.isEmpty {
                merged = snapshot
                didUpdate = true
            } else {
                for (region, list) in snapshot where !list.isEmpty {
                    if let existing = merged[region], !existing.isEmpty {
                        continue
                    }
                    merged[region] = list
                    didUpdate = true
                }
            }
            guard didUpdate else { return }
            communityCache = merged
            communityCacheIsStale = false
#if DEBUG
            if bottomTab == .topRated, topRatedSort == .community {
                communityInstrumentation.resetFirstRender()
                let count = merged[topRatedRegion]?.count ?? merged[.all]?.count ?? 0
                communityInstrumentation.markWarmCache(region: topRatedRegion, count: count)
            }
#endif
        }
    }

    private func applyKeyboardReceiveModifiers<V: View>(_ view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                guard let info = notification.userInfo,
                      let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let overlap = max(0, frameValue.height - currentBottomSafeAreaInset())
                keyboardHeight = overlap
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
    }

    private func applySearchAndAlertModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: searchQuery) { _, newValue in
                searchDebounceTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if isSearchOverlayPresented {
                    if selectedCategoryOption != nil || selectedCuisineOption != nil {
                        if selectedCategoryOption?.query != trimmed || trimmed.isEmpty {
                            selectedCategoryOption = nil
                        }
                        if selectedCuisineOption?.query != trimmed || trimmed.isEmpty {
                            selectedCuisineOption = nil
                        }
                    }
                }
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
    }

    private func applyOverlayAndSheetModifiers<V: View>(_ view: V) -> some View {
        view
            .sheet(item: $selectedPlace) { place in
                PlaceDetailView(place: place)
                    .environmentObject(favoritesStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: appleSheetSelection) { selection in
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
    }

    private var appleSheetSelection: Binding<ApplePlaceSelection?> {
        Binding(
            get: { Self.appleDetailsEnabled ? selectedApplePlace : nil },
            set: { newValue in
                if Self.appleDetailsEnabled {
                    selectedApplePlace = newValue
                } else {
                    selectedApplePlace = nil
                }
            }
        )
    }

    private func presentApplePlace(_ mapItem: MKMapItem) {
        guard Self.appleDetailsEnabled else { return }
        selectedApplePlace = ApplePlaceSelection(mapItem: mapItem)
    }

    private func applyPostOverlayModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: bottomTab) { _, tab in
#if DEBUG
                if tab != .topRated {
                    communityInstrumentation.markCancel(reason: "Exited community tab before completion")
                    communityInstrumentation.resetAll()
                }
#endif
                activeDropdown = nil
                switch tab {
                case .favorites:
                    selectedApplePlace = nil
                    if let selected = selectedPlace,
                       !favoritesStore.contains(id: selected.id) {
                        selectedPlace = nil
                    }
                case .places:
                    // Only center on first use; otherwise preserve existing map state
                    if let location = locationManager.lastKnownLocation, !hasCenteredOnUser {
                        centerMap(on: location)
                    }
                    refreshVisiblePlaces()
                    refreshVisiblePins()
                case .newSpots:
                    selectedApplePlace = nil
                    isSearchOverlayPresented = false
                    // Ensure the global dataset is loaded so New Spots IDs resolve reliably
                    viewModel.ensureGlobalDataset()
                    preloadNewSpotDetailsIfNeeded()
                    refreshVisiblePlaces()
                    refreshVisiblePins()
                case .topRated:
                    selectedApplePlace = nil
                    if let selected = selectedPlace,
                       !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                        selectedPlace = nil
                    }
                    scheduleCommunityPrecomputationIfNeeded()
                    if topRatedSort == .community {
                        scheduleCommunityPrecomputationIfNeeded()
                    }
#if DEBUG
                    if topRatedSort == .community {
                        communityInstrumentation.startLoadIfNeeded(
                            metadata: "Tab switch -> community region=\(topRatedRegion.rawValue)"
                        )
                    }
#endif
                case .more:
                    selectedApplePlace = nil
                    selectedPlace = nil
                    isSearchOverlayPresented = false
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
#if DEBUG
                if newValue == .community, bottomTab == .topRated {
                    communityInstrumentation.startLoadIfNeeded(
                        metadata: "Sort -> community region=\(topRatedRegion.rawValue)"
                    )
                } else {
                    communityInstrumentation.markCancel(reason: "Community sort deactivated")
                    communityInstrumentation.resetAll()
                }
#endif
            }
            .onChange(of: topRatedRegion) { _, _ in
                if bottomTab == .topRated,
                   let selected = selectedPlace,
                   !topRatedDisplay.contains(where: { $0.id == selected.id }) {
                    selectedPlace = nil
                }
#if DEBUG
                if bottomTab == .topRated, topRatedSort == .community {
                    if let cached = communityCache[topRatedRegion] {
                        communityInstrumentation.resetFirstRender()
                        communityInstrumentation.markWarmCache(region: topRatedRegion, count: cached.count)
                    } else {
                        communityInstrumentation.markCancel(reason: "Region changed before data ready")
                        communityInstrumentation.startLoadIfNeeded(
                            metadata: "Region -> \(topRatedRegion.rawValue)"
                        )
                    }
                }
#endif
            }
            .onChange(of: isSearchOverlayPresented) { _, presented in
                if presented {
                    activeDropdown = nil
                }
            }
    }

    private var mapShell: some View {
        let isMapHidden = bottomTab == .newSpots || bottomTab == .more
        return ZStack(alignment: .top) {
            // Always keep MapTabContainer in hierarchy to preserve map state (zoom, position)
            MapTabContainer(
                mapRegion: $mapRegion,
                selectedPlace: $selectedPlace,
                selectedApplePlace: $selectedApplePlace,
                pins: mapPins,
                places: mapPlaces,
                appleMapItems: mapAppleItems,
                isLoading: viewModel.isLoading,
                shouldShowLoadingIndicator: viewModel.isLoading && viewModel.places.isEmpty,
                onRegionChange: { region in
                    let effective = RegionGate.enforcedRegion(for: region)
                    appleHalalSearch.search(in: effective)
                    if shouldFetchDetails(for: region), !isRefinedFilterActive {
                        viewModel.regionDidChange(to: region, filter: selectedFilter)
                    }
                    refreshVisiblePlaces()
                    refreshVisiblePins()
                    if bottomTab == .favorites, isFavoritesPanelCollapsed, !isFavoritesPanelPinnedCollapsed {
                        scheduleFavoritesPanelReopen()
                    }
                },
                onPinSelected: { pin in
                    selectedApplePlace = nil
                    pinSelectionTask?.cancel()
                    if let cached = viewModel.place(with: pin.id) {
                        selectedPlace = cached
                        return
                    }
                    pinSelectionTask = Task { @MainActor in
                        defer { pinSelectionTask = nil }
                        if let place = await viewModel.fetchPlaceDetails(for: pin.id) {
                            selectedPlace = place
                        }
                    }
                },
                onPlaceSelected: { place in
                    selectedPlace = place
                },
                onAppleItemSelected: { mapItem in
                    presentApplePlace(mapItem)
                },
                onMapTap: {
                    if activeDropdown != nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeDropdown = nil
                        }
                    }
                    collapseFavoritesPanelForMapInteraction()
                }
            )
            .opacity(isMapHidden ? 0 : 1)
            .allowsHitTesting(!isMapHidden)

            // Search bar and filter bar - only show when map is visible
            if !isMapHidden {
                VStack(alignment: .leading, spacing: 0) {
                    searchBar
                    mapFilterBar
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .overlay(alignment: .top) {
                    if isUserOutsideCoverage {
                        CoverageBannerView(onLearnMore: { bottomTab = .more })
                            .padding(.top, 64)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }

            // TopRatedScreen overlays the map
            if bottomTab == .topRated {
                TopRatedScreen(
                    places: topRatedDisplay,
                    sortOption: topRatedSort,
                    region: topRatedRegion,
                    userLocation: locationManager.lastKnownLocation,
                    googleData: $topRatedGoogleDataCache,
                    cachedGoogleOrder: topRatedGoogleOrderCache[topRatedGoogleOrderKey],
                    onGoogleOrderChange: { topRatedGoogleOrderCache[topRatedGoogleOrderKey] = $0 },
                    topInset: currentTopSafeAreaInset(),
                    bottomInset: currentBottomSafeAreaInset(),
                    isCommunityLoading: topRatedSort == .community
                        && communityCache[.all] == nil
                        && (communityPrecomputeTask != nil || !viewModel.hasTrustedCommunityDataset()),
                    onSelect: { place in
                        focus(on: place)
                    },
                    onSortChange: { topRatedSort = $0 },
                    onRegionChange: { topRatedRegion = $0 }
                )
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
                .ignoresSafeArea()
            }

            // NewSpotsScreen completely covers map
            if bottomTab == .newSpots {
                NewSpotsScreen(
                    spots: featuredNewSpots,
                    spotlight: spotlightEntry,
                    userLocation: locationManager.lastKnownLocation,
                    topInset: currentTopSafeAreaInset(),
                    onSelect: { place in
                        selectedPlace = place
                    }
                )
                .environmentObject(favoritesStore)
            }

            // MoreScreen completely covers map
            if bottomTab == .more {
                MoreScreen(
                    isUserOutsideCoverage: isUserOutsideCoverage,
                    onSwitchToMap: { bottomTab = .places }
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if bottomTab == .places || bottomTab == .favorites {
                locateMeButton
                    .padding(.top, locateButtonTopPadding)
                    .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowBottomOverlay {
                bottomOverlay
            }
        }
    }

    private var shouldShowBottomOverlay: Bool {
        !(bottomTab == .more && keyboardHeight > 0)
    }

    private var filterBarItems: [MapFilterBarItem] {
        [.filter(.all), .filter(.fullyHalal), .filter(.partialHalal), .filter(.zabihahHalal), .category]
    }

    private var categoryDropdownItems: [CategoryDropdownItem] {
        var items: [CategoryDropdownItem] = [
            .active(.foodTruck),
            .active(.highEnd),
            .active(.new)
        ]
#if DEBUG
        items.append(contentsOf: [
            .disabled(.cafe, statusText: "Coming soon"),
            .disabled(.dessert, statusText: "Coming soon"),
            .disabled(.grocery, statusText: "Coming soon")
        ])
#endif
        return items
    }

    private var mapFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filterBarItems) { item in
                        switch item {
                        case .filter(let filter):
                            let isSelected = filter == selectedFilter
                            mapFilterChip(
                                title: item.title,
                                iconName: item.iconName,
                                trailingIconName: nil,
                                isSelected: isSelected
                            ) {
                                guard !isSelected else {
                                    activeDropdown = nil
                                    return
                                }
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedFilter = filter
                                    activeDropdown = nil
                                    selectedCategoryOption = nil
                                    selectedCuisineOption = nil
                                }
                                if !searchQuery.isEmpty {
                                    searchQuery = ""
                                }
                            }
                        case .category:
                            let hasSelection = selectedCategoryOption != nil
                            let isActive = activeDropdown == .category
                            let trailing = isActive ? "chevron.up" : "chevron.down"
                            mapFilterChip(
                                title: item.title,
                                iconName: item.iconName,
                                trailingIconName: trailing,
                                isSelected: hasSelection || isActive
                            ) {
                                toggleDropdown(.category)
                            }
                        case .cuisine:
                            let hasSelection = selectedCuisineOption != nil
                            let isActive = activeDropdown == .cuisine
                            let trailing = isActive ? "chevron.up" : "chevron.down"
                            mapFilterChip(
                                title: item.title,
                                iconName: item.iconName,
                                trailingIconName: trailing,
                                isSelected: hasSelection || isActive
                            ) {
                                toggleDropdown(.cuisine)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if let dropdown = activeDropdown {
                dropdownMenu(for: dropdown)
                    .transition(
                        AnyTransition.offset(y: -12)
                            .combined(with: .opacity)
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
    }

    private func mapFilterChip(
        title: String,
        iconName: String?,
        trailingIconName: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let trailingIconName {
                    Image(systemName: trailingIconName)
                        .font(.system(size: 11, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : Color(.systemBackground).opacity(0.96)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.35)
                            : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.22)
                    : Color.black.opacity(0.05),
                radius: isSelected ? 9 : 5,
                y: isSelected ? 4 : 3
            )
        }
        .buttonStyle(.plain)
    }

    private enum BottomTab: CaseIterable, Identifiable {
        case places
        case topRated
        case newSpots
        case favorites
        case more

        var id: Self { self }

        var title: String {
            switch self {
            case .places: return "Map"
            case .topRated: return "Top Rated"
            case .newSpots: return "New Spots"
            case .favorites: return "Favorites"
            case .more: return "More"
            }
        }

        var systemImage: String {
            switch self {
            case .places: return "map"
            case .topRated: return "star.fill"
            case .newSpots: return "mappin.and.ellipse" // distinct; suggests new pins/places
            case .favorites: return "heart.fill"
            case .more: return "ellipsis.circle"
            }
        }

        var contentOffsetX: CGFloat {
            switch self {
            case .topRated:
                return -3
            case .favorites:
                return 3
            case .places, .newSpots, .more:
                return 0
            }
        }

        // Optical offsets to center SF Symbols within a uniform icon box.
        var iconOffset: CGSize {
            let minorOffset = CGSize(width: 0.12, height: -0.12)
            switch self {
            case .places:
                return CGSize(width: 0.3, height: 0.12)
            case .topRated:
                return minorOffset
            case .newSpots:
                return CGSize(width: 0.5, height: 0.88)
            case .favorites:
                return CGSize(width: 0.12, height: 0.25)
            case .more:
                return CGSize(width: 0.06, height: 0.06)
            }
        }
    }

    private struct CoverageBannerView: View {
        let onLearnMore: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Currently available in NYC + Long Island")
                        .font(.subheadline.weight(.semibold))
                    Text("If you're outside NY, you can still explore NYC/LI on the map.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("More") { onLearnMore() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Currently available in NYC and Long Island. Tap More for details.")
        }
    }

    private struct MoreScreen: View {
        let isUserOutsideCoverage: Bool
        let onSwitchToMap: () -> Void

        @Environment(\.openURL) private var openURL
        @State private var isShowingAbout = false

        var body: some View {
            NavigationStack {
                List {
                    Section("Coverage") {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NYC + Long Island")
                                    .font(.subheadline.weight(.semibold))
                                Text(isUserOutsideCoverage
                                     ? "You're currently outside the coverage area."
                                     : "You're in the current coverage area.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("About this app") { isShowingAbout = true }
                        Button("Go to Map") { onSwitchToMap() }
                    }

                    Section("Privacy") {
                        if let privacyURL = privacyPolicyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        } else {
                            NavigationLink("Privacy Policy") {
                                PrivacyPolicyView()
                            }
                        }
                    }

                    Section("Support & Feedback") {
                        if let supportURL = supportURL {
                            Link("Support", destination: supportURL)
                        }

                        NavigationLink("Submit feedback / suggest a place") {
                            FeedbackFormView()
                        }

                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }
                .navigationTitle("More")
                .sheet(isPresented: $isShowingAbout) {
                    AboutSheetView()
                }
            }
        }

        private var privacyPolicyURL: URL? {
            infoURL(for: "PRIVACY_POLICY_URL")
        }

        private var supportURL: URL? {
            infoURL(for: "SUPPORT_URL")
        }

        private func infoURL(for key: String) -> URL? {
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            return URL(string: trimmed)
        }
    }

    private struct AboutSheetView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Coverage")
                            .font(.headline)
                        Text("This version is currently focused on NYC + Long Island.")
                            .foregroundStyle(.secondary)

                        Text("Data sources")
                            .font(.headline)
                        Text("Halal status comes from our curated dataset.")
                            .foregroundStyle(.secondary)
                        Text("Maps, ratings, and photos are powered by Google Maps and Google Places (fetched via our backend with short-term caching).")
                            .foregroundStyle(.secondary)
                        Text("Apple Maps is used only for directions and fallback place details.")
                            .foregroundStyle(.secondary)

                        Text("Disclaimer")
                            .font(.headline)
                        Text("Halal information is best-effort and can change. Please confirm with the restaurant if you have strict requirements.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                }
                .navigationTitle("About")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private struct PrivacyPolicyView: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy Policy")
                        .font(.title3.weight(.semibold))

                    Text("Last updated: 2026-01-23")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Group {
                        Text("What we collect")
                            .font(.headline)
                        Text("• Location (optional): used to show nearby halal restaurants.\n• Search text: used to find matching places.\n• Favorites: stored on your device.")
                            .foregroundStyle(.secondary)

                        Text("How we use it")
                            .font(.headline)
                        Text("We use this data to power map search, nearby results, and app functionality.")
                            .foregroundStyle(.secondary)

                        Text("Sharing")
                            .font(.headline)
                        Text("Map/search requests are sent to our backend (Supabase) to fetch place data. Google Places details (ratings/photos) are fetched via our backend proxy.")
                            .foregroundStyle(.secondary)

                        Text("Tracking")
                            .font(.headline)
                        Text("We do not use data for cross-app tracking and do not request App Tracking Transparency permission.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                }
                .padding(18)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct FeedbackFormView: View {
        @Environment(\.openURL) private var openURL

        @State private var placeName = ""
        @State private var message = ""
        @State private var contact = ""
        private let messagePlaceholder =
            "Let us know if there's a restaurant we should add to our map, " +
            "if something isn't halal, or any feedback!"

        var body: some View {
            Form {
                Section("Restaurant (optional)") {
                    TextField("Restaurant name", text: $placeName)
                        .textInputAutocapitalization(.words)
                }

                Section("Message") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $message)
                            .frame(minHeight: 140)
                        if message.isEmpty {
                            Text(messagePlaceholder)
                                .foregroundStyle(Color(UIColor.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .padding(.trailing, 5)
                                .allowsHitTesting(false)
                        }
                    }
                }

                Section("Your contact (optional)") {
                    TextField("Email or @handle", text: $contact)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Button("Send") {
                    sendEmailFallback()
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
        }

        private func sendEmailFallback() {
            let to = (Bundle.main.object(forInfoDictionaryKey: "SUPPORT_EMAIL") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTo = (to?.isEmpty == false) ? to! : "support@example.com"

            let subject = "HalalFood feedback"
            var body = ""
            if !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body += "Restaurant: \(placeName)\n\n"
            }
            body += message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body += "\n\nContact: \(contact)"
            }

            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
            if let url = URL(string: "mailto:\(resolvedTo)?subject=\(encodedSubject)&body=\(encodedBody)") {
                openURL(url)
            }
        }
    }

    private var bottomTabBar: some View {
        // Off‑white bar; keep original height but visually center content by nudging it down.
        let barHeight = max(52, currentScreenHeight() / 20)
        let safe = currentBottomSafeAreaInset()
        let contentOffset = CGFloat(min(14, max(6, safe * 0.28)))
        let iconPointSize: CGFloat = 20
        let iconBoxSize: CGFloat = 24
        let horizontalInset: CGFloat = 12
        let interTabSpacing: CGFloat = 6
        return VStack(spacing: 0) {
            Divider().background(Color.black.opacity(0.06))
            HStack(spacing: interTabSpacing) {
                ForEach(BottomTab.allCases) { tab in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        bottomTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .resizable()
                                .scaledToFit()
                                .font(.system(size: iconPointSize, weight: .semibold))
                                .frame(width: iconBoxSize, height: iconBoxSize)
                                .offset(x: tab.iconOffset.width, y: tab.iconOffset.height)
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .allowsTightening(true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(
                            x: tab.contentOffsetX,
                            y: contentOffset
                        ) // nudge content without changing bar height
                        .foregroundStyle(bottomTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalInset)
            .frame(height: barHeight)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var bottomOverlay: some View {
        let showFavorites = bottomTab == .favorites
        return VStack(spacing: showFavorites ? 16 : 0) {
            if showFavorites {
                Group {
                    if isFavoritesPanelCollapsed {
                        FavoritesCollapsedPill(
                            count: favoritesDisplay.count,
                            onTap: {
                                favoritesPanelTask?.cancel()
                                favoritesPanelTask = nil
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isFavoritesPanelCollapsed = false
                                }
                                isFavoritesPanelPinnedCollapsed = false
                            }
                        )
                    } else {
                        FavoritesPanel(
                            favorites: favoritesDisplay,
                            sortOption: favoritesSort,
                            onSelect: { snapshot in
                                focus(on: resolvedPlace(for: snapshot))
                            },
                            onCollapse: {
                                favoritesPanelTask?.cancel()
                                favoritesPanelTask = nil
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isFavoritesPanelCollapsed = true
                                }
                                isFavoritesPanelPinnedCollapsed = true
                            },
                            onSortChange: { favoritesSort = $0 }
                        )
                    }
                }
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
            }
            bottomTabBar
        }
        .padding(.bottom, bottomOverlayPadding)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: bottomTab)
        .animation(.easeInOut(duration: 0.2), value: isFavoritesPanelCollapsed)
    }

    private var bottomOverlayPadding: CGFloat {
        0 // flush with bottom; bar manages its own safe area
    }

    // No chip-style labels anymore; the bar uses icons + labels above.

    private var searchBar: some View {
        Button {
            activeDropdown = nil
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
                    let tightSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    centerMap(on: location, span: tightSpan)
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
        guard selectedCategoryOption == nil, selectedCuisineOption == nil else { return }
        if !searchQuery.isEmpty {
            searchQuery = ""
        }
    }

    private func toggleDropdown(_ dropdown: MapFilterDropdown) {
        if bottomTab != .places {
            bottomTab = .places
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeDropdown = activeDropdown == dropdown ? nil : dropdown
        }
    }

    private func selectCategory(_ option: CategoryFilterOption?) {
        if bottomTab != .places {
            bottomTab = .places
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            if let option {
                if selectedCategoryOption == option {
                    selectedCategoryOption = nil
                } else {
                    selectedCategoryOption = option
                    selectedCuisineOption = nil
                }
            } else {
                selectedCategoryOption = nil
            }
            activeDropdown = nil
        }
        if selectedCategoryOption != nil {
            viewModel.ensureGlobalDataset()
            if selectedCategoryOption == .new {
                preloadNewSpotDetailsIfNeeded()
            }
        }
        if let current = selectedCategoryOption {
            if current == .highEnd || current == .new {
                searchQuery = ""
            } else {
                searchQuery = current.query
            }
        } else if let cuisine = selectedCuisineOption {
            searchQuery = cuisine.query
        } else {
            searchQuery = ""
        }
        filterSelectionVersion &+= 1
        refreshVisiblePlaces()
        if selectedCategoryOption == nil && selectedCuisineOption == nil {
            refreshVisiblePins()
            if shouldFetchDetails(for: mapRegion) {
                viewModel.regionDidChange(to: mapRegion, filter: selectedFilter)
            }
        }
    }

    private func selectCuisine(_ option: CuisineFilterOption?) {
        if bottomTab != .places {
            bottomTab = .places
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            if let option {
                if selectedCuisineOption == option {
                    selectedCuisineOption = nil
                } else {
                    selectedCuisineOption = option
                    selectedCategoryOption = nil
                }
            } else {
                selectedCuisineOption = nil
            }
            activeDropdown = nil
        }
        if selectedCuisineOption != nil {
            viewModel.ensureGlobalDataset()
        }
        if let current = selectedCuisineOption {
            searchQuery = current.query
        } else if let category = selectedCategoryOption {
            if category == .highEnd || category == .new {
                searchQuery = ""
            } else {
                searchQuery = category.query
            }
        } else {
            searchQuery = ""
        }
        filterSelectionVersion &+= 1
        refreshVisiblePlaces()
        if selectedCategoryOption == nil && selectedCuisineOption == nil {
            refreshVisiblePins()
            if shouldFetchDetails(for: mapRegion) {
                viewModel.regionDidChange(to: mapRegion, filter: selectedFilter)
            }
        }
    }

    @ViewBuilder
    private func dropdownMenu(for dropdown: MapFilterDropdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch dropdown {
            case .category:
                Text("Categories")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                categoryDropdownButtons(
                    options: categoryDropdownItems,
                    selected: selectedCategoryOption,
                    onSelect: { selectCategory($0) },
                    onClear: { selectCategory(nil) }
                )
            case .cuisine:
                Text("Cuisines")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                dropdownButtons(
                    options: CuisineFilterOption.allCases,
                    selected: selectedCuisineOption,
                    onSelect: { selectCuisine($0) },
                    onClear: { selectCuisine(nil) }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.96))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    private func dropdownButtons<Option: Identifiable & Equatable>(
        options: [Option],
        selected: Option?,
        onSelect: @escaping (Option) -> Void,
        onClear: @escaping () -> Void
    ) -> some View where Option: CustomStringConvertible {
        VStack(alignment: .leading, spacing: 6) {
            dropdownOptionButton(
                title: "Select All",
                isSelected: selected == nil,
                action: onClear
            )
            ForEach(options) { option in
                dropdownOptionButton(
                    title: option.description,
                    isSelected: option == selected,
                    action: { onSelect(option) }
                )
            }
        }
    }

    private func categoryDropdownButtons(
        options: [CategoryDropdownItem],
        selected: CategoryFilterOption?,
        onSelect: @escaping (CategoryFilterOption) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            dropdownOptionButton(
                title: "Select All",
                isSelected: selected == nil,
                action: onClear
            )
            ForEach(options) { option in
                let isSelected = option.option == selected
                dropdownOptionButton(
                    title: option.title,
                    isSelected: isSelected,
                    isEnabled: option.isEnabled,
                    trailingText: option.statusText
                ) {
                    guard option.isEnabled, let category = option.option else { return }
                    onSelect(category)
                }
            }
        }
    }

    private func dropdownOptionButton(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(
                isSelected
                    ? Color.accentColor
                    : Color.primary.opacity(isEnabled ? 0.9 : 0.45)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color.primary.opacity(isEnabled ? 0.04 : 0.02)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
        refreshVisiblePins()
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
        presentApplePlace(mapItem)
        isSearchOverlayPresented = false
        refreshVisiblePlaces()
        refreshVisiblePins()
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
        if isRefinedFilterActive {
            let baseVersion = viewModel.globalDatasetVersion
            let localVersion = baseVersion == 0 ? viewModel.filteredPlacesVersion : 0
            let cacheVersion = baseVersion &+ localVersion &+ filterSelectionVersion &+ filterSelectionSignature
            if refinedPlacesCacheVersion != cacheVersion {
                refinedPlacesCacheVersion = cacheVersion
                refinedPlacesCache = filteredPlaces
            }
            let next = viewportCache.slice(for: mapRegion, version: cacheVersion, source: refinedPlacesCache)
            if next != visiblePlaces {
                visiblePlaces = next
                scheduleThumbnailPrefetch(for: next)
            }
            return
        }
        let base = filteredPlaces
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseVersion = trimmed.isEmpty ? viewModel.filteredPlacesVersion : viewModel.searchResultsVersion
        let version = baseVersion &+ filterSelectionVersion &+ filterSelectionSignature
        let next = viewportCache.slice(for: mapRegion, version: version, source: base)
        if next != visiblePlaces {
            visiblePlaces = next
            scheduleThumbnailPrefetch(for: next)
        }
    }

    private func scheduleThumbnailPrefetch(for places: [Place]) {
        thumbnailPrefetchTask?.cancel()
        let candidates = places.filter { $0.hasGooglePlaceID }
        guard !candidates.isEmpty else { return }

        let prioritized = prioritizeThumbnailPlaces(candidates)
        let firstBatch = Array(prioritized.prefix(6))
        let remaining = Array(prioritized.dropFirst(6))

        for place in firstBatch {
            GooglePlaceThumb.prefetch(for: place)
        }

        guard !remaining.isEmpty else { return }
        thumbnailPrefetchTask = Task.detached {
            try? await Task.sleep(nanoseconds: 900_000_000)
            for place in remaining.prefix(24) {
                if Task.isCancelled { break }
                GooglePlaceThumb.prefetch(for: place)
            }
        }
    }

    private func prioritizeThumbnailPlaces(_ places: [Place]) -> [Place] {
        guard let userLocation = locationManager.lastKnownLocation else { return places }
        return places.sorted { lhs, rhs in
            let lhsDist = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
                .distance(from: userLocation)
            let rhsDist = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
                .distance(from: userLocation)
            return lhsDist < rhsDist
        }
    }

    private func refreshVisiblePins() {
        guard bottomTab == .places || bottomTab == .newSpots else { return }
        guard !isRefinedFilterActive else { return }
        let scopedPins = pinsStore.pins.filteredByCurrentGeoScope()
        let filteredPins: [PlacePin]
        switch selectedFilter {
        case .all:
            filteredPins = scopedPins
        case .fullyHalal:
            filteredPins = scopedPins.filter { $0.halalStatus == .only }
        case .partialHalal:
            filteredPins = scopedPins.filter { $0.halalStatus == .yes }
        case .zabihahHalal:
            // Zabihah filter uses full Place data, pins don't have certifierOrg
            // This case is guarded by isRefinedFilterActive check above
            filteredPins = []
        }
        let bbox = mapRegion.bbox
        let next = filteredPins.filter { pin in
            pin.latitude >= bbox.south && pin.latitude <= bbox.north &&
                pin.longitude >= bbox.west && pin.longitude <= bbox.east
        }
        if next != visiblePins {
            visiblePins = next
        }
    }

    private func shouldFetchDetails(for region: MKCoordinateRegion) -> Bool {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        return span < HalalMapView.dotSpanThreshold
    }

    private func startInitialPinsLoaderIfNeeded() {
        guard showInitialPinsLoader else { return }
        guard initialPinsProgress < 0.1 else { return }
        initialPinsProgress = 0.08
        withAnimation(.linear(duration: 8.0)) {
            initialPinsProgress = 0.92
        }
    }

    private func completeInitialPinsLoader() {
        guard showInitialPinsLoader else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            initialPinsProgress = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            showInitialPinsLoader = false
        }
    }

    private func collapseFavoritesPanelForMapInteraction() {
        guard bottomTab == .favorites else { return }
        guard !isFavoritesPanelPinnedCollapsed else { return }
        if !isFavoritesPanelCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) {
                isFavoritesPanelCollapsed = true
            }
        }
        scheduleFavoritesPanelReopen()
    }

    private func scheduleFavoritesPanelReopen() {
        guard !isFavoritesPanelPinnedCollapsed else { return }
        favoritesPanelTask?.cancel()
        favoritesPanelTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: favoritesPanelAutoExpandNanoseconds)
            } catch {
                return
            }
            guard bottomTab == .favorites else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isFavoritesPanelCollapsed = false
            }
            favoritesPanelTask = nil
        }
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
                Spacer()
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
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
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

private struct InitialPinsLoadingView: View {
    let progress: Double
    let isRefreshing: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.976, green: 0.969, blue: 0.957)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                logoView

                Text("Get ready for the latest and greatest halal spots")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.373, green: 0.369, blue: 0.365))
                    .multilineTextAlignment(.center)
                    .frame(width: 260)

                if let errorMessage, !isRefreshing {
                    Text("We couldn't load the map yet. \(errorMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 12) {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.borderedProminent)
                        Button("Continue", action: onContinue)
                            .buttonStyle(.bordered)
                    }
                } else if isRefreshing || progress < 1.0 {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.accentColor)
                }
            }
            .padding(.top, 12)
        }
    }

    private var logoView: some View {
        Image("FinalAppLogo_Real")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Rawa logo")
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                if let rating = place.displayRating, rating > 0 {
                    let count = place.displayRatingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        if count > 0 {
                            Text("(\(count) \(ratingLabel))")
                        }
                    }
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
    let userLocation: CLLocation?
    @Binding var googleData: [UUID: GooglePlaceData]
    let cachedGoogleOrder: [UUID]?
    let onGoogleOrderChange: ([UUID]) -> Void
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isCommunityLoading: Bool
    let onSelect: (Place) -> Void
    let onSortChange: (TopRatedSortOption) -> Void
    let onRegionChange: (TopRatedRegion) -> Void

    private let detailColor = Color.primary.opacity(0.65)
    @State private var visibleLimit: Int = 10
    @State private var googleOrderedIDs: [UUID] = []
    @State private var didFinalizeGoogleOrder = false
    private let pageSize: Int = 10

    var body: some View {
        let effectivePlaces = displayPlaces
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Rated")
                        .font(.title3.weight(.semibold))
                    if !effectivePlaces.isEmpty {
                        Text("\(effectivePlaces.count) places")
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

            if effectivePlaces.isEmpty {
                if sortOption == .community && isCommunityLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading community favorites...")
                            .font(.footnote)
                            .foregroundStyle(detailColor)
                    }
                } else {
                    Text("No matches yet. Try a different location.")
                        .font(.footnote)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let displayPairs: [(offset: Int, element: Place)] = {
                    let enumerated = Array(effectivePlaces.enumerated())
                    return Array(enumerated.prefix(visibleLimit))
                }()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Card style similar to NewSpots
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(displayPairs, id: \.element.id) { index, place in
                                if index != 0 {
                                    Divider()
                                        .background(Color.black.opacity(0.06))
                                }
                                Button { onSelect(place) } label: {
                                    TopRatedRow(
                                        place: place,
                                        googleData: validGoogleData(for: place.id),
                                        rank: (sortOption == .community ? index + 1 : nil),
                                        showRating: sortOption != .community
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(18)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 9)

                        if visibleLimit < effectivePlaces.count {
                            Button {
                                visibleLimit = min(visibleLimit + pageSize, effectivePlaces.count)
                            } label: {
                                Text("Show More")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        Color(.secondarySystemGroupedBackground),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .task(id: displayPairs.map { $0.element.id }) {
                    // Warm prefetch a small number of thumbnails for instant display
                    let prioritized = prioritizePlacesByDistance(displayPairs.map { $0.element })
                    for place in prioritized.prefix(pageSize) {
                        if place.isYelpBacked {
                            TopRatedPhotoThumb.prefetch(for: place.id)
                        } else {
                            GooglePlaceThumb.prefetch(for: place)
                        }
                    }
                }
            }
        }
        .padding(.top, topInset + 24)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomInset + 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .onChange(of: sortOption) { _, _ in
            visibleLimit = pageSize
        }
        .onChange(of: googleTaskKey) { _, _ in
            didFinalizeGoogleOrder = false
            googleOrderedIDs = resolvedInitialGoogleOrder()
        }
        .onChange(of: region) { _, _ in
            visibleLimit = pageSize
        }
        .onChange(of: places.count) { _, _ in
            visibleLimit = min(visibleLimit, max(places.count, pageSize))
        }
        .task(id: googleTaskKey) {
            didFinalizeGoogleOrder = false
            googleOrderedIDs = resolvedInitialGoogleOrder()
            await loadGoogleData(for: googleLoadPlaces)
        }
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

    private var displayPlaces: [Place] {
        switch sortOption {
        case .community:
            return places
        case .google:
            return googleSortedPlaces
        }
    }

    private var googleSortedPlaces: [Place] {
        let candidates = places.filter { $0.hasGooglePlaceID }
        guard !candidates.isEmpty else { return [] }
        let order = resolvedGoogleOrder(for: candidates)
        guard !order.isEmpty else { return candidates }
        let rank: [UUID: Int] = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return candidates.sorted { lhs, rhs in
            let lhsRank = rank[lhs.id] ?? Int.max
            let rhsRank = rank[rhs.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func validGoogleData(for id: UUID) -> GooglePlaceData? {
        guard let data = googleData[id], !data.isExpired else { return nil }
        return data
    }

    private func resolvedInitialGoogleOrder() -> [UUID] {
        let candidateIDs = Set(places.filter(\.hasGooglePlaceID).map(\.id))
        if let cachedGoogleOrder {
            let filtered = cachedGoogleOrder.filter { candidateIDs.contains($0) }
            if !filtered.isEmpty { return filtered }
        }
        return places.filter(\.hasGooglePlaceID).map(\.id)
    }

    private func resolvedGoogleOrder(for candidates: [Place]) -> [UUID] {
        let candidateIDs = Set(candidates.map(\.id))
        if !googleOrderedIDs.isEmpty {
            let filtered = googleOrderedIDs.filter { candidateIDs.contains($0) }
            if !filtered.isEmpty { return filtered }
        }
        return computeGoogleSortOrder(for: candidates)
    }

    private func computeGoogleSortOrder(for candidates: [Place]) -> [UUID] {
        let scored: [(id: UUID, name: String, rating: Double, count: Int)] = candidates.map { place in
            let data = validGoogleData(for: place.id)
            let rating = data?.rating ?? -1
            let count = data?.reviewCount ?? 0
            return (place.id, place.name, rating, count)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted.map(\.id)
    }

    private func finalizeGoogleOrderIfNeeded(for candidates: [Place]) {
        guard sortOption == .google else { return }
        guard !didFinalizeGoogleOrder else { return }
        let order = computeGoogleSortOrder(for: candidates)
        guard !order.isEmpty else { return }
        didFinalizeGoogleOrder = true
        googleOrderedIDs = order
        onGoogleOrderChange(order)
    }

    private var googleTaskKey: [UUID] {
        googleLoadPlaces.map(\.id)
    }

    private var googleLoadPlaces: [Place] {
        switch sortOption {
        case .community:
            return Array(places.prefix(visibleLimit))
        case .google:
            // Important: keep the task key stable. `displayPlaces` depends on `googleData` (sorting),
            // which would otherwise cause repeated reloads as `googleData` updates.
            return Array(places.prefix(visibleLimit))
        }
    }

    private func loadGoogleData(for places: [Place]) async {
        let candidates = prioritizePlacesByDistance(places.filter { $0.hasGooglePlaceID })
        guard !candidates.isEmpty else { return }
        let maxConcurrent = 4
        let priorityCount = min(10, candidates.count)
        let priority = Array(candidates.prefix(priorityCount))
        let remaining = Array(candidates.dropFirst(priorityCount))

        func refresh(_ place: Place) {
            Task {
                if let refreshed = try? await GooglePlaceCache.shared.fetchPlace(for: place, forceRefresh: true) {
                    await MainActor.run {
                        googleData[place.id] = refreshed
                    }
                }
            }
        }

        func resolve(_ place: Place) async {
            if Task.isCancelled { return }

            if let existing = await MainActor.run(body: { googleData[place.id] }) {
                if existing.isExpired {
                    await MainActor.run {
                        googleData[place.id] = nil
                    }
                } else {
                    if existing.isNearExpiry {
                        refresh(place)
                    }
                    return
                }
            }

            if let cached = await GooglePlaceCache.shared.cachedData(for: place) {
                await MainActor.run {
                    googleData[place.id] = cached
                }
                if cached.isNearExpiry {
                    refresh(place)
                }
                return
            }

            do {
                let data = try await GooglePlaceCache.shared.fetchPlace(for: place)
                await MainActor.run {
                    googleData[place.id] = data
                }
            } catch {
                // ignore list failures
            }
        }

        for place in priority {
            await resolve(place)
        }
        await MainActor.run {
            finalizeGoogleOrderIfNeeded(for: candidates)
        }

        guard !remaining.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = remaining.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let next = iterator.next() else { break }
                group.addTask { await resolve(next) }
            }

            while await group.next() != nil {
                if Task.isCancelled { break }
                if let next = iterator.next() {
                    group.addTask { await resolve(next) }
                }
            }
        }
    }

    private func prioritizePlacesByDistance(_ places: [Place]) -> [Place] {
        guard let userLocation else { return places }
        return places.sorted { lhs, rhs in
            let lhsDist = CLLocation(latitude: lhs.coordinate.latitude,
                                     longitude: lhs.coordinate.longitude)
                .distance(from: userLocation)
            let rhsDist = CLLocation(latitude: rhs.coordinate.latitude,
                                     longitude: rhs.coordinate.longitude)
                .distance(from: userLocation)
            return lhsDist < rhsDist
        }
    }
}

private struct TopRatedRow: View {
    let place: Place
    let googleData: GooglePlaceData?
    let rank: Int?
    let showRating: Bool

    private let detailColor = Color.primary.opacity(0.75)
    @State private var cuisine: String?
    @State private var displayLocOverride: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TopRatedThumbnail(place: place, yelpPhotoURL: nil)
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

                if showRating {
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
            if let rank {
                CommunityRankBadge(rank: rank)
            }
        }
        .task(id: place.id) {
            await loadCuisine()
        }
    }

    @ViewBuilder
    private func ratingView() -> some View {
        let fallbackRating = place.displayRating
        let fallbackCount = place.displayRatingCount
        if let data = googleData, let rating = data.rating, rating > 0 {
            ratingLine(rating: rating, count: data.reviewCount)
        } else if place.hasGooglePlaceID, googleData == nil {
            Text("Loading Google rating…")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        } else if let rating = fallbackRating, rating > 0 {
            ratingLine(rating: rating, count: fallbackCount)
        } else if place.hasGooglePlaceID, googleData != nil {
            noReviewsLine()
        } else {
            noReviewsLine()
        }
    }

    @ViewBuilder
    private func ratingLine(rating: Double, count: Int?) -> some View {
        let hasCount = (count ?? 0) > 0
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
            Text(String(format: "%.1f", rating))
                .font(.subheadline)
                .foregroundStyle(Color.primary)
            if hasCount {
                Text("(\(reviewLabel(for: count)))")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func noReviewsLine() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text("No reviews yet")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .italic()
        }
    }

    private func reviewLabel(for count: Int?) -> String {
        guard let count, count > 0 else { return "No reviews yet" }
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

    private func titleCase(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " / ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func loadCuisine() async {
        if cuisine != nil && displayLocOverride != nil { return }

        let baselineLocation = displayLocOverride ?? place.displayLocation ?? DisplayLocationResolver.display(for: place)
        if let baselineLocation {
            await MainActor.run {
                if self.displayLocOverride == nil {
                    self.displayLocOverride = baselineLocation
                }
            }
        }

        if cuisine == nil || displayLocOverride == nil {
            if let cached = await TopRatedCuisineResolver.shared.cachedEntry(for: place.id) {
                await MainActor.run {
                    if let cachedCuisine = cached.cuisine {
                        self.cuisine = cachedCuisine
                    }
                    if let cachedDisplay = cached.displayLocation {
                        self.displayLocOverride = cachedDisplay
                    }
                }
                if cached.cuisine != nil {
                    return
                }
            }
        } else {
            return
        }

        let resolved = await TopRatedCuisineResolver.shared.resolve(for: place)
        await MainActor.run {
            if let resolvedCuisine = resolved.cuisine {
                self.cuisine = resolvedCuisine
            }
            if let resolvedDisplay = resolved.displayLocation {
                self.displayLocOverride = resolvedDisplay
            }
        }
    }

    private func shortLocation() -> String? {
        if let override = displayLocOverride, !override.isEmpty { return override }
        if let persisted = place.displayLocation, !persisted.isEmpty { return persisted }
        return DisplayLocationResolver.display(for: place)
    }

}

private struct TopRatedThumbnail: View {
    let place: Place
    let yelpPhotoURL: URL?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if place.isYelpBacked {
                if let url = yelpPhotoURL {
                    CachedAsyncImage(url: url) {
                        placeholder
                    } failure: {
                        placeholder
                    }
                    .scaledToFill()
                } else {
                    placeholder
                }
            } else {
                GooglePlaceThumb(place: place)
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
}

private struct YelpInlineRatingView: View {
    let rating: Double
    let reviewCount: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(sourceLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
            YelpReviewRibbon(rating: rating, style: .inline)
                .accessibilityHidden(true)
            Text(String(format: "%.1f", rating))
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        }
    }

    private var sourceLabel: String {
        guard let reviewCount, reviewCount > 0 else { return "Yelp" }
        return "Yelp (\(shortReviewCount(reviewCount)))"
    }

    private func shortReviewCount(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        return "\(count)"
    }
}

private struct CommunityRankBadge: View {
    let rank: Int

    var body: some View {
        let symbolName: String? = rank <= 50 ? "\(rank).circle.fill" : nil
        let gold = Color(red: 0.95, green: 0.76, blue: 0.20)
        HStack(spacing: 6) {
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

private actor TopRatedCuisineResolver {
    struct Entry: Sendable {
        let cuisine: String?
        let displayLocation: String?
    }

    static let shared = TopRatedCuisineResolver()

    private var cache: [UUID: Entry] = [:]
    private var inflight: [UUID: Task<Entry, Never>] = [:]

    func cachedEntry(for id: UUID) -> Entry? {
        cache[id]
    }

    func resolve(for place: Place) async -> Entry {
        if let cached = cache[place.id] { return cached }
        if let pending = inflight[place.id] { return await pending.value }

        let task = Task<Entry, Never> { await Self.fetchEntry(for: place) }
        inflight[place.id] = task
        let entry = await task.value
        cache[place.id] = entry
        inflight.removeValue(forKey: place.id)
        return entry
    }

    private struct SourceRow: Decodable {
        let display_location: String?
        let category_label: String?
        let source_raw: SourceRaw?
    }

    private struct SourceRaw: Decodable {
        let categories: [String]?
        let display_location: String?
    }

    private static func fetchEntry(for place: Place) async -> Entry {
        var cuisine: String? = place.categoryLabel
        var display = place.displayLocation ?? DisplayLocationResolver.display(for: place)

        if cuisine == nil, !place.categories.isEmpty {
            cuisine = preferredCuisine(from: Array(place.categories))
        }

        guard let supabaseURL = Env.optionalURL(),
              let anonKey = Env.optionalAnonKey() else {
            return Entry(cuisine: cuisine, displayLocation: display)
        }

        do {
            guard var comps = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else {
                return Entry(cuisine: cuisine, displayLocation: display)
            }
            var path = comps.path
            if !path.hasSuffix("/") { path.append("/") }
            path.append("rest/v1/place_google_ready")
            comps.path = path
            comps.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(place.id.uuidString)"),
                URLQueryItem(name: "select", value: "category_label,source_raw,display_location")
            ]
            guard let requestURL = comps.url else {
                return Entry(cuisine: cuisine, displayLocation: display)
            }
            var req = URLRequest(url: requestURL)
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let row = try? JSONDecoder().decode([SourceRow].self, from: data).first {
                    if let label = row.category_label?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !label.isEmpty {
                        cuisine = label
                    }
                    if cuisine == nil, let categories = row.source_raw?.categories {
                        cuisine = preferredCuisine(from: categories)
                    }
                    if let disp = row.display_location?.trimmingCharacters(in: .whitespacesAndNewlines), !disp.isEmpty {
                        display = disp
                    } else if let disp = row.source_raw?.display_location, !disp.isEmpty {
                        display = disp
                    }
                }
            }
        } catch {
            // Ignore network failures; fall back to existing data.
        }

        if display == nil {
            display = DisplayLocationResolver.display(for: place)
        }

        return Entry(cuisine: cuisine, displayLocation: display)
    }

    private static func preferredCuisine(from categories: [String]) -> String? {
        let cats = categories.map { $0.lowercased() }
        let excluded: Set<String> = [
            "halal","gluten_free","vegan","vegetarian",
            "coffee","cafes","coffeeandtea","tea","bubbletea",
            "desserts","donuts","bakeries","icecream",
            "bars","cocktailbars","beerbar","wine_bars"
        ]

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

        for c in cats where !excluded.contains(c) {
            if let label = map[c] {
                return label
            }
        }

        if let first = cats.first(where: { !excluded.contains($0) }) {
            return titleCase(first)
        }

        return nil
    }

    private static func titleCase(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " / ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Display Location Resolver (Neighborhood, Borough) with caching
nonisolated private enum DisplayLocationResolver {
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

nonisolated private final class DisplayLocationCache {
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

nonisolated private extension String {
    func capitalizedWords() -> String {
        self.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
    func caseInsensitiveEquals(_ other: String) -> Bool { self.lowercased() == other.lowercased() }
}

// Thumbnail loader for Top Rated rows
private struct TopRatedPhotoThumb: View {
    let placeID: UUID
    let showsPlaceholder: Bool
    @State private var imageURL: URL?
    @State private var attempted = false
    nonisolated(unsafe) private static var urlCache: [UUID: URL] = [:]
    nonisolated private static let urlCacheLock = NSLock()
    nonisolated private static let supabaseObjectPrefix = "/storage/v1/object/public/"
    nonisolated private static let supabaseRenderPrefix = "/storage/v1/render/image/public/"
    nonisolated private static let preferredWidth = "320"
    nonisolated private static let preferredQuality = "75"

    init(placeID: UUID, showsPlaceholder: Bool = true) {
        self.placeID = placeID
        self.showsPlaceholder = showsPlaceholder
    }

    var body: some View {
        if let local = TopRatedPhotoThumb.localThumb(for: placeID) {
            Image(uiImage: local)
                .resizable()
                .scaledToFill()
        } else {
            let resolvedURL = imageURL ?? TopRatedPhotoThumb.cachedURL(for: placeID)
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

    @ViewBuilder
    private var placeholder: some View {
        if showsPlaceholder {
            ZStack {
                Color.gray.opacity(0.25)
                Text("🍔🥤")
                    .font(.system(size: 24))
                    .opacity(0.9)
            }
        } else {
            Color.clear
        }
    }

    private struct PhotoRow: Decodable { let image_url: String }
    @MainActor
    private func loadThumbnailAndCuisine() async {
        guard let supabaseURL = Env.optionalURL(),
              let anonKey = Env.optionalAnonKey() else { return }
        do {
            // Build place_photo URL
            guard var comps = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else { return }
            var p = comps.path
            if !p.hasSuffix("/") { p.append("/") }
            p.append("rest/v1/place_photo")
            comps.path = p
            comps.queryItems = [
                URLQueryItem(name: "place_id", value: "eq.\(placeID.uuidString)"),
                URLQueryItem(name: "order", value: "priority.asc"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let requestURL = comps.url else { return }
            var req = URLRequest(url: requestURL)
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            req.setValue("public", forHTTPHeaderField: "Accept-Profile")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let row = try? JSONDecoder().decode([PhotoRow].self, from: data).first,
                   let url = URL(string: row.image_url) {
                    let optimized = TopRatedPhotoThumb.optimizedURL(from: url)
                    imageURL = optimized
                    TopRatedPhotoThumb.setCachedURL(optimized, for: placeID)
                    Task.detached {
                        await TopRatedPhotoThumb.warmCache(for: optimized)
                    }
                }
            }
        } catch {
            // ignore failures silently
        }
    }

    // Check for a bundled asset named "thumb_<UUID>"
    nonisolated private static func localThumb(for id: UUID) -> UIImage? {
        let name = "thumb_\(id.uuidString)"
        return UIImage(named: name)
    }

    // Allow prefetching from TopRatedScreen
    nonisolated static func prefetch(for id: UUID) {
        if localThumb(for: id) != nil { return }
        if cachedURL(for: id) != nil { return }
        guard let supabaseURL = Env.optionalURL(),
              let anonKey = Env.optionalAnonKey() else { return }
        Task.detached {
            do {
                guard var comps = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else { return }
                var p = comps.path
                if !p.hasSuffix("/") { p.append("/") }
                p.append("rest/v1/place_photo")
                comps.path = p
                comps.queryItems = [
                    URLQueryItem(name: "place_id", value: "eq.\(id.uuidString)"),
                    URLQueryItem(name: "order", value: "priority.asc"),
                    URLQueryItem(name: "limit", value: "1")
                ]
                guard let requestURL = comps.url else { return }
                var req = URLRequest(url: requestURL)
                req.setValue(anonKey, forHTTPHeaderField: "apikey")
                req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
                req.setValue("public", forHTTPHeaderField: "Accept-Profile")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let row = try? JSONDecoder().decode([PhotoRow].self, from: data).first,
                       let url = URL(string: row.image_url) {
                        let optimized = optimizedURL(from: url)
                        setCachedURL(optimized, for: id)
                        // Fetch to populate image cache
                        await warmCache(for: optimized)
                    }
                }
            } catch { /* ignore */ }
        }
    }

    nonisolated static func optimizedURL(from original: URL) -> URL {
        if let host = original.host, host.contains("yelpcdn.com") {
            let absolute = original.absoluteString
            if absolute.hasSuffix("/o.jpg") {
                if let converted = URL(string: absolute.replacingOccurrences(of: "/o.jpg", with: "/l.jpg")) {
                    return converted
                }
            }
        }

        guard let baseURL = Env.optionalURL(),
              let baseHost = baseURL.host,
              original.host == baseHost,
              original.path.contains(supabaseObjectPrefix) else {
            return original
        }

        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme
        components?.host = baseHost
        if let path = components?.path {
            components?.path = path.replacingOccurrences(of: supabaseObjectPrefix, with: supabaseRenderPrefix)
        }
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "width" || $0.name == "quality" }
        items.append(URLQueryItem(name: "width", value: preferredWidth))
        items.append(URLQueryItem(name: "quality", value: preferredQuality))
        components?.queryItems = items
        return components?.url ?? original
    }

    nonisolated static func cache(_ url: URL, for id: UUID) async {
        setCachedURL(url, for: id)
    }

    nonisolated private static func warmCache(for url: URL) async {
        await YelpImagePolicy.warm(url)
    }

    nonisolated private static func cachedURL(for id: UUID) -> URL? {
        urlCacheLock.lock(); defer { urlCacheLock.unlock() }
        return urlCache[id]
    }

    nonisolated private static func setCachedURL(_ url: URL, for id: UUID) {
        urlCacheLock.lock()
        urlCache[id] = url
        urlCacheLock.unlock()
    }
}

nonisolated private enum GoogleThumbURLBuilder {
    private static let preferredWidth = "640"

    static func thumbnailURL(from original: URL) -> URL {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            return original
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "maxwidth" || $0.name == "maxWidthPx" }
        items.append(URLQueryItem(name: "maxwidth", value: preferredWidth))
        components.queryItems = items
        return components.url ?? original
    }
}

nonisolated private enum GooglePhotoURLBuilder {
    private static let thumbnailWidth = "1200"
    private static let fullWidth = "1600"

    static func thumbnailURL(from original: URL) -> URL {
        applyWidth(thumbnailWidth, to: original)
    }

    static func fullSizeURL(from original: URL) -> URL {
        applyWidth(fullWidth, to: original)
    }

    private static func applyWidth(_ width: String, to original: URL) -> URL {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            return original
        }
        guard components.path.contains("google_places_proxy/photo") else {
            return original
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "maxwidth" || $0.name == "maxWidthPx" }
        items.append(URLQueryItem(name: "maxwidth", value: width))
        components.queryItems = items
        return components.url ?? original
    }
}

private actor GooglePhotoResolver {
    static let shared = GooglePhotoResolver()
    private var urlCache: [UUID: URL] = [:]
    private var inflight: [UUID: Task<URL?, Never>] = [:]

    nonisolated func prefetch(_ place: Place) {
        Task { await prefetchInternal(place) }
    }

    func fetchThumbnailURL(for place: Place) async -> URL? {
        if let cached = urlCache[place.id] { return cached }
        if let cachedPhotos = await PlacePhotoCache.shared.get(place.id),
           let first = cachedPhotos.first(where: { $0.isGooglePhoto }),
           let url = URL(string: first.imageUrl) {
            let thumb = GoogleThumbURLBuilder.thumbnailURL(from: url)
            urlCache[place.id] = thumb
            return thumb
        }
        if let task = inflight[place.id] { return await task.value }

        let task = Task<URL?, Never> {
            if let cachedPhotos = await PlacePhotoCache.shared.get(place.id),
               let first = cachedPhotos.first(where: { $0.isGooglePhoto }),
               let url = URL(string: first.imageUrl) {
                return GoogleThumbURLBuilder.thumbnailURL(from: url)
            }

            if let directID = resolveGooglePlaceID(for: place),
               let data = try? await GooglePlaceCache.shared.fetchPlace(
                   googlePlaceID: directID,
                   placeID: place.id
               ),
               let url = await cacheGooglePhotosIfNeeded(data, placeID: place.id) {
                return url
            }

            guard let data = try? await GooglePlaceCache.shared.fetchPlace(for: place),
                  let url = await cacheGooglePhotosIfNeeded(data, placeID: place.id) else {
                return nil
            }
            return url
        }

        inflight[place.id] = task
        let url = await task.value
        inflight[place.id] = nil
        if let url { urlCache[place.id] = url }
        return url
    }

    private func prefetchInternal(_ place: Place) async {
        if urlCache[place.id] != nil { return }
        if inflight[place.id] != nil { return }
        _ = await fetchThumbnailURL(for: place)
    }

    private func cacheGooglePhotosIfNeeded(_ data: GooglePlaceData, placeID: UUID) async -> URL? {
        guard let first = data.photos.first,
              let url = URL(string: first.url) else {
            return nil
        }
        let googlePhotos = data.photos.map { photo in
            let externalId = photo.reference.map { "google:\($0)" } ?? "google:\(photo.position)"
            return PlacePhoto(
                placeID: placeID,
                position: photo.position,
                url: photo.url,
                attribution: photo.attribution,
                source: "google",
                externalId: externalId,
                width: photo.width,
                height: photo.height
            )
        }
        await PlacePhotoCache.shared.set(
            placeID,
            photos: googlePhotos,
            expiresAt: data.effectiveExpiresAt
        )
        return GoogleThumbURLBuilder.thumbnailURL(from: url)
    }

    private func resolveGooglePlaceID(for place: Place) -> String? {
        if let id = normalizedGooglePlaceID(place.googlePlaceID) { return id }
        if let parsed = googlePlaceID(from: place.googleMapsURL) { return parsed }
        if let parsed = googlePlaceID(from: place.externalID) { return parsed }
        return nil
    }

    private func normalizedGooglePlaceID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }
        return trimmed
    }

    private func googlePlaceID(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("google:") {
            let stripped = String(trimmed.dropFirst(7))
            return normalizedGooglePlaceID(stripped)
        }
        return extractGooglePlaceID(from: trimmed)
    }

    private func extractGooglePlaceID(from raw: String) -> String? {
        let marker = "place_id:"
        if let range = raw.range(of: marker) {
            let tail = raw[range.upperBound...]
            let candidate = tail.split { $0 == "&" || $0 == " " || $0 == "," || $0 == ")" }.first
            return normalizedGooglePlaceID(candidate.map(String.init))
        }
        return normalizedGooglePlaceID(raw)
    }
}

private struct GooglePlaceThumb: View {
    let place: Place
    @State private var imageURL: URL?
    @State private var cacheRefresh: Int = 0

    var body: some View {
        let resolvedURL = imageURL
        Group {
            if let url = resolvedURL {
                CachedAsyncImage(url: url) {
                    placeholder
                } failure: {
                    placeholder
                }
                .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: loadToken) {
            await loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .placePhotoCacheDidUpdate)) { notice in
            guard let placeID = notice.userInfo?["placeID"] as? UUID else { return }
            guard placeID == place.id else { return }
            cacheRefresh &+= 1
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

    nonisolated static func prefetch(for place: Place) {
        GooglePhotoResolver.shared.prefetch(place)
    }

    private var loadKey: String {
        let trimmed = place.googlePlaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? place.id.uuidString : "\(place.id.uuidString)-\(trimmed)"
    }

    private var loadToken: String {
        "\(loadKey)-\(cacheRefresh)"
    }

    private func loadImage() async {
        if imageURL != nil { return }
        if let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
            await MainActor.run {
                imageURL = url
            }
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if imageURL == nil, let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
            await MainActor.run {
                imageURL = url
            }
        }
    }
}

private struct GooglePlaceThumbWithFallback: View {
    let place: Place
    let fallback: AnyView
    @State private var imageURL: URL?
    @State private var cacheRefresh: Int = 0

    var body: some View {
        ZStack {
            fallback
            if let url = imageURL {
                CachedAsyncImage(url: url) {
                    EmptyView()
                } failure: {
                    EmptyView()
                }
                .scaledToFill()
            }
        }
        .task(id: loadToken) {
            await loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .placePhotoCacheDidUpdate)) { notice in
            guard let placeID = notice.userInfo?["placeID"] as? UUID else { return }
            guard placeID == place.id else { return }
            cacheRefresh &+= 1
        }
    }

    private var loadKey: String {
        let trimmed = place.googlePlaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? place.id.uuidString : "\(place.id.uuidString)-\(trimmed)"
    }

    private var loadToken: String {
        "\(loadKey)-\(cacheRefresh)"
    }

    private func loadImage() async {
        if imageURL != nil { return }
        if let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
            await MainActor.run {
                imageURL = url
            }
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if imageURL == nil, let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
            await MainActor.run {
                imageURL = url
            }
        }
    }
}

actor YelpDiskCache {
    static let shared = YelpDiskCache()

    private enum Constants {
        static let directoryName = "hf-yelp-cache-v1"
        static let indexFilename = "index.json"
        static let version = 1
        static let maxSizeBytes = 150 * 1024 * 1024
    }

    private enum EntryKind: String, Codable {
        case business
        case image
    }

    private struct CacheEntry: Codable {
        let filename: String
        var sizeBytes: Int
        var expiresAt: Date
        var lastAccess: Date
        let kind: EntryKind
    }

    private struct CacheIndex: Codable {
        let version: Int
        var entries: [String: CacheEntry]
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var entries: [String: CacheEntry] = [:]
    private var didLoadIndex = false
    private var didRunMaintenance = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = cachesDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        indexURL = directoryURL.appendingPathComponent(Constants.indexFilename)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func runMaintenanceIfNeeded() {
        loadIndexIfNeeded()
        guard !didRunMaintenance else { return }
        didRunMaintenance = true
        purgeExpiredEntries(now: Date())
        removeMissingFiles()
        trimIfNeeded()
        persistIndex()
    }

    func cachedBusiness(for yelpID: String) -> YelpBusinessData? {
        loadIndexIfNeeded()
        let key = businessKey(yelpID)
        guard var entry = entries[key], entry.kind == .business else { return nil }
        let now = Date()
        if entry.expiresAt <= now {
            removeEntry(forKey: key, entry: entry)
            persistIndex()
            return nil
        }
        let url = directoryURL.appendingPathComponent(entry.filename)
        guard let data = try? Data(contentsOf: url),
              let cached = try? decoder.decode(YelpBusinessData.self, from: data) else {
            removeEntry(forKey: key, entry: entry)
            persistIndex()
            return nil
        }
        let effectiveExpiresAt = min(entry.expiresAt, cached.effectiveExpiresAt)
        if effectiveExpiresAt <= now {
            removeEntry(forKey: key, entry: entry)
            persistIndex()
            return nil
        }
        entry.expiresAt = effectiveExpiresAt
        entry.lastAccess = now
        entries[key] = entry
        persistIndex()
        return cached
    }

    func storeBusiness(_ data: YelpBusinessData) {
        loadIndexIfNeeded()
        let key = businessKey(data.yelpID)
        let expiresAt = data.effectiveExpiresAt
        let now = Date()
        if expiresAt <= now {
            if let entry = entries[key] {
                removeEntry(forKey: key, entry: entry)
                persistIndex()
            }
            return
        }
        let filename = filename(for: key, kind: .business)
        let url = directoryURL.appendingPathComponent(filename)
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: [.atomic])
            let entry = CacheEntry(
                filename: filename,
                sizeBytes: encoded.count,
                expiresAt: expiresAt,
                lastAccess: now,
                kind: .business
            )
            entries[key] = entry
            trimIfNeeded()
            persistIndex()
        } catch {
            // ignore
        }
    }

    func cachedImageData(for url: URL) -> Data? {
        loadIndexIfNeeded()
        let key = imageKey(url)
        guard var entry = entries[key], entry.kind == .image else { return nil }
        let now = Date()
        if entry.expiresAt <= now {
            removeEntry(forKey: key, entry: entry)
            persistIndex()
            return nil
        }
        let fileURL = directoryURL.appendingPathComponent(entry.filename)
        guard let data = try? Data(contentsOf: fileURL) else {
            removeEntry(forKey: key, entry: entry)
            persistIndex()
            return nil
        }
        entry.lastAccess = now
        entries[key] = entry
        persistIndex()
        return data
    }

    func storeImageData(_ data: Data, for url: URL, expiresAt: Date) {
        loadIndexIfNeeded()
        let key = imageKey(url)
        let now = Date()
        let maxExpiresAt = now.addingTimeInterval(YelpBusinessData.maxCacheAge)
        let effectiveExpiresAt = min(expiresAt, maxExpiresAt)
        if effectiveExpiresAt <= now {
            if let entry = entries[key] {
                removeEntry(forKey: key, entry: entry)
                persistIndex()
            }
            return
        }
        let filename = filename(for: key, kind: .image)
        let fileURL = directoryURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: [.atomic])
            let entry = CacheEntry(
                filename: filename,
                sizeBytes: data.count,
                expiresAt: effectiveExpiresAt,
                lastAccess: now,
                kind: .image
            )
            entries[key] = entry
            trimIfNeeded()
            persistIndex()
        } catch {
            // ignore
        }
    }

    private func businessKey(_ yelpID: String) -> String {
        "business:\(yelpID)"
    }

    private func imageKey(_ url: URL) -> String {
        "image:\(url.absoluteString)"
    }

    private func filename(for key: String, kind: EntryKind) -> String {
        let ext = kind == .business ? "json" : "img"
        return hashedFilename(for: key, fileExtension: ext)
    }

    private func loadIndexIfNeeded() {
        guard !didLoadIndex else { return }
        didLoadIndex = true
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let index = try decoder.decode(CacheIndex.self, from: data)
            guard index.version == Constants.version else {
                resetCache()
                return
            }
            entries = index.entries
        } catch {
            entries = [:]
        }
    }

    private func resetCache() {
        entries = [:]
        try? fileManager.removeItem(at: directoryURL)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func persistIndex() {
        let index = CacheIndex(version: Constants.version, entries: entries)
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            // ignore
        }
    }

    private func purgeExpiredEntries(now: Date) {
        let expiredKeys = entries.filter { $0.value.expiresAt <= now }.map(\.key)
        for key in expiredKeys {
            if let entry = entries[key] {
                removeEntry(forKey: key, entry: entry)
            }
        }
    }

    private func removeMissingFiles() {
        let missingKeys = entries.filter { entry in
            let url = directoryURL.appendingPathComponent(entry.value.filename)
            return !fileManager.fileExists(atPath: url.path)
        }.map(\.key)
        for key in missingKeys {
            entries.removeValue(forKey: key)
        }
    }

    private func trimIfNeeded() {
        var totalBytes = entries.values.reduce(0) { $0 + $1.sizeBytes }
        guard totalBytes > Constants.maxSizeBytes else { return }
        let sorted = entries.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, entry) in sorted {
            removeEntry(forKey: key, entry: entry)
            totalBytes -= entry.sizeBytes
            if totalBytes <= Constants.maxSizeBytes { break }
        }
    }

    private func removeEntry(forKey key: String, entry: CacheEntry) {
        let url = directoryURL.appendingPathComponent(entry.filename)
        try? fileManager.removeItem(at: url)
        entries.removeValue(forKey: key)
    }

    private func hashedFilename(for key: String, fileExtension: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(fileExtension)"
    }
}

nonisolated private enum YelpImagePolicy {
    private static let yelpHost = "yelpcdn.com"
    private static let yelpSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func isYelpURL(_ url: URL) -> Bool {
        url.host?.contains(yelpHost) == true
    }

    static func fetchData(from url: URL) async throws -> Data {
        if isYelpURL(url) {
            if let cached = await YelpDiskCache.shared.cachedImageData(for: url) {
                return cached
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await yelpSession.data(for: request)
            let expiresAt = Date().addingTimeInterval(YelpBusinessData.maxCacheAge)
            await YelpDiskCache.shared.storeImageData(data, for: url, expiresAt: expiresAt)
            return data
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    static func warm(_ url: URL) async {
        do {
            _ = try await fetchData(from: url)
        } catch {
            // ignore
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
            let data = try await YelpImagePolicy.fetchData(from: url)
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
            guard hostingController.view != nil else { return }
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
    private let memory = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "ImageCache.IO")
    private let folderURL: URL

    private init() {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let legacyURL = caches.appendingPathComponent("hf-image-cache", isDirectory: true)
        folderURL = caches.appendingPathComponent("hf-image-cache-v2", isDirectory: true)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        memory.countLimit = 512
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        image(forKey: url.absoluteString)
    }

    func store(_ image: UIImage, for url: URL) {
        store(image, forKey: url.absoluteString)
    }

    func image(forKey key: String) -> UIImage? {
        let nsKey = key as NSString
        if let img = memory.object(forKey: nsKey) { return img }
        if isYelpKey(key) { return nil }
        let path = folderURL.appendingPathComponent(String(key.hashValue))
        if let data = try? Data(contentsOf: path), let img = UIImage(data: data) {
            memory.setObject(img, forKey: nsKey)
            return img
        }
        return nil
    }

    func store(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString
        memory.setObject(image, forKey: nsKey)
        if isYelpKey(key) { return }
        let path = folderURL.appendingPathComponent(String(key.hashValue))
        ioQueue.async {
            if let data = image.jpegData(compressionQuality: 0.92) ?? image.pngData() {
                try? data.write(to: path, options: .atomic)
            }
        }
    }

    private func isYelpKey(_ key: String) -> Bool {
        key.lowercased().contains("yelpcdn.com")
    }
}

struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    let url: URL?
    let cacheKey: String?
    let maxPixelSize: CGFloat?
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?

    init(url: URL?,
         cacheKey: String? = nil,
         maxPixelSize: CGFloat? = nil,
         @ViewBuilder placeholder: @escaping () -> Placeholder,
         @ViewBuilder failure: @escaping () -> Failure) {
        self.url = url
        self.cacheKey = cacheKey
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder
        self.failure = failure
    }

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
#if DEBUG
        var loadSpan: PerformanceSpan?
        var loadSource = "unknown"
        if let url {
            loadSpan = PerformanceMetrics.begin(
                event: .imageLoad,
                metadata: url.absoluteString
            )
        } else {
            loadSource = "missing-url"
        }
        defer {
            PerformanceMetrics.end(loadSpan, metadata: "source=\(loadSource)")
        }
#endif
        guard let url else { return }
        let resolvedCacheKey = cacheKey ?? url.absoluteString
        if let cached = ImageCache.shared.image(forKey: resolvedCacheKey) {
            image = cached
#if DEBUG
            loadSource = "cache"
#endif
            return
        }
        do {
            let data = try await YelpImagePolicy.fetchData(from: url)
            if let img = decodeImage(from: data) {
                ImageCache.shared.store(img, forKey: resolvedCacheKey)
                image = img
#if DEBUG
                loadSource = "network"
#endif
            }
        } catch {
#if DEBUG
            loadSource = "error"
            PerformanceMetrics.point(
                event: .imageLoad,
                metadata: "Failed for \(url.absoluteString) – \(error.localizedDescription)"
            )
#endif
            // ignore
        }
    }

    private func decodeImage(from data: Data) -> UIImage? {
        guard let maxPixelSize else { return UIImage(data: data) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let maxPixel = max(1, Int(maxPixelSize))
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

actor PlacePhotoCache {
    static let shared = PlacePhotoCache()
    private struct Entry {
        let photos: [PlacePhoto]
        let expiresAt: Date?
    }

    private var map: [UUID: Entry] = [:]

    func get(_ id: UUID) -> [PlacePhoto]? {
        guard let entry = map[id] else { return nil }
        if let expiresAt = entry.expiresAt, expiresAt <= Date() {
            map[id] = nil
            return nil
        }
        return entry.photos
    }

    func set(_ id: UUID, photos: [PlacePhoto], expiresAt: Date? = nil) {
        map[id] = Entry(photos: photos, expiresAt: expiresAt)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .placePhotoCacheDidUpdate,
                object: nil,
                userInfo: ["placeID": id]
            )
        }
    }
}

private extension Notification.Name {
    static let placePhotoCacheDidUpdate = Notification.Name("placePhotoCacheDidUpdate")
}

private enum GooglePlaceCacheError: Error {
    case missingGooglePlaceID
}

private actor GooglePlaceCache {
    static let shared = GooglePlaceCache()

    private var cache: [String: GooglePlaceData] = [:]
    private var inflight: [String: Task<GooglePlaceData, Error>] = [:]
    private var googleIDByPlaceID: [UUID: String] = [:]
    private var idInflight: [UUID: Task<String?, Never>] = [:]
    private var lastRefreshAttempt: [String: Date] = [:]
    private let refreshThrottle: TimeInterval = 60 * 10

    func cachedData(for place: Place) async -> GooglePlaceData? {
        guard let googlePlaceID = place.googlePlaceID ?? googleIDByPlaceID[place.id] else { return nil }
        if let cached = cache[googlePlaceID] {
            if cached.isExpired {
                cache[googlePlaceID] = nil
            } else {
                googleIDByPlaceID[place.id] = googlePlaceID
                return cached
            }
        }
        return nil
    }

    /// Direct cache lookup by Google Place ID (for FavoritesPanel pre-population)
    func cachedDataByID(_ googlePlaceID: String) -> GooglePlaceData? {
        guard let cached = cache[googlePlaceID], !cached.isExpired else { return nil }
        return cached
    }

    func fetchPlace(for place: Place, forceRefresh: Bool = false) async throws -> GooglePlaceData {
        guard let googlePlaceID = await resolveGooglePlaceID(for: place) else {
            throw GooglePlaceCacheError.missingGooglePlaceID
        }
        return try await fetchPlace(googlePlaceID: googlePlaceID, placeID: place.id, forceRefresh: forceRefresh)
    }

    func fetchPlace(
        googlePlaceID: String,
        placeID: UUID? = nil,
        forceRefresh: Bool = false
    ) async throws -> GooglePlaceData {
        if let placeID { googleIDByPlaceID[placeID] = googlePlaceID }

        if !forceRefresh {
            if let cached = cache[googlePlaceID], !cached.isExpired {
                return cached
            }
        }

        if let task = inflight[googlePlaceID] {
            let data = try await task.value
            if let placeID { googleIDByPlaceID[placeID] = googlePlaceID }
            return data
        }

        if forceRefresh {
            let cached = cache[googlePlaceID]
            if let cached, !cached.isExpired, shouldThrottleRefresh(for: googlePlaceID) {
                return cached
            }
            markRefreshAttempt(for: googlePlaceID)
        }

        let task = Task { try await GooglePlacesAPI.fetchPlace(googlePlaceID: googlePlaceID) }
        inflight[googlePlaceID] = task
        defer { inflight[googlePlaceID] = nil }

        let data = try await task.value
        if !data.isExpired {
            cache[googlePlaceID] = data
        } else {
            cache[googlePlaceID] = nil
        }
        if let placeID { googleIDByPlaceID[placeID] = googlePlaceID }
        return data
    }

    private func resolveGooglePlaceID(for place: Place) async -> String? {
        if let googlePlaceID = normalizedGooglePlaceID(place.googlePlaceID) {
            googleIDByPlaceID[place.id] = googlePlaceID
            return googlePlaceID
        }
        if let cached = googleIDByPlaceID[place.id] { return cached }
        if let parsed = googlePlaceID(from: place.googleMapsURL) ?? googlePlaceID(from: place.externalID) {
            googleIDByPlaceID[place.id] = parsed
            return parsed
        }
        if let task = idInflight[place.id] {
            return await task.value
        }

        let task = Task { () -> String? in
            if let metadata = try? await PlaceAPI.fetchPlaceGoogleMetadata(placeID: place.id) {
                if let id = normalizedGooglePlaceID(metadata.googlePlaceID) {
                    return id
                }
                if let parsed = googlePlaceID(from: metadata.googleMapsURL)
                    ?? googlePlaceID(from: metadata.externalID) {
                    return parsed
                }
            }
            guard let dto = try? await PlaceAPI.fetchPlaceDetails(placeID: place.id),
                  let resolved = Place(dto: dto) else {
                return nil
            }
            return normalizedGooglePlaceID(resolved.googlePlaceID)
        }
        idInflight[place.id] = task

        let id = await task.value
        idInflight[place.id] = nil
        if let id {
            googleIDByPlaceID[place.id] = id
        }
        return id
    }

    private func normalizedGooglePlaceID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }
        return trimmed
    }

    private func googlePlaceID(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("google:") {
            let stripped = String(trimmed.dropFirst(7))
            return normalizedGooglePlaceID(stripped)
        }
        return extractGooglePlaceID(from: trimmed)
    }

    private func extractGooglePlaceID(from raw: String) -> String? {
        let marker = "place_id:"
        if let range = raw.range(of: marker) {
            let tail = raw[range.upperBound...]
            let candidate = tail.split { $0 == "&" || $0 == " " || $0 == "," || $0 == ")" }.first
            return normalizedGooglePlaceID(candidate.map(String.init))
        }
        return normalizedGooglePlaceID(raw)
    }

    private func shouldThrottleRefresh(for googlePlaceID: String) -> Bool {
        if let last = lastRefreshAttempt[googlePlaceID],
           Date().timeIntervalSince(last) < refreshThrottle {
            return true
        }
        return false
    }

    private func markRefreshAttempt(for googlePlaceID: String) {
        lastRefreshAttempt[googlePlaceID] = Date()
    }
}

private enum YelpBusinessCacheError: Error {
    case notYelpBacked
    case missingYelpID
}

private actor YelpBusinessCache {
    static let shared = YelpBusinessCache()

    private var cache: [String: YelpBusinessData] = [:]
    private var inflight: [String: Task<YelpBusinessData, Error>] = [:]
    private var yelpIDByPlaceID: [UUID: String] = [:]
    private var idInflight: [UUID: Task<String?, Never>] = [:]
    private var lastRefreshAttempt: [String: Date] = [:]
    private let refreshThrottle: TimeInterval = 60 * 10

    func cachedData(for place: Place) async -> YelpBusinessData? {
        guard let yelpID = place.yelpID ?? yelpIDByPlaceID[place.id] else { return nil }
        if let cached = cache[yelpID] {
            if cached.isExpired {
                cache[yelpID] = nil
            } else {
                yelpIDByPlaceID[place.id] = yelpID
                return cached
            }
        }
        if let cached = await YelpDiskCache.shared.cachedBusiness(for: yelpID) {
            cache[yelpID] = cached
            yelpIDByPlaceID[place.id] = yelpID
            return cached
        }
        return nil
    }

    func fetchBusiness(for place: Place, forceRefresh: Bool = false) async throws -> YelpBusinessData {
        guard place.isYelpBacked else { throw YelpBusinessCacheError.notYelpBacked }
        guard let yelpID = await resolveYelpID(for: place) else {
            throw YelpBusinessCacheError.missingYelpID
        }
        return try await fetchBusiness(yelpID: yelpID, placeID: place.id, forceRefresh: forceRefresh)
    }

    func fetchBusiness(
        yelpID: String,
        placeID: UUID? = nil,
        forceRefresh: Bool = false
    ) async throws -> YelpBusinessData {
        if let placeID { yelpIDByPlaceID[placeID] = yelpID }

        if !forceRefresh {
            if let cached = cache[yelpID], !cached.isExpired {
                return cached
            }
            if let cached = await YelpDiskCache.shared.cachedBusiness(for: yelpID) {
                cache[yelpID] = cached
                return cached
            }
        }

        if let task = inflight[yelpID] {
            let data = try await task.value
            if let placeID { yelpIDByPlaceID[placeID] = yelpID }
            return data
        }

        if forceRefresh {
            var cached = cache[yelpID]
            if cached == nil {
                cached = await YelpDiskCache.shared.cachedBusiness(for: yelpID)
            }
            if let cached, !cached.isExpired, shouldThrottleRefresh(for: yelpID) {
                cache[yelpID] = cached
                return cached
            }
            markRefreshAttempt(for: yelpID)
        }

        let task = Task { try await YelpAPI.fetchBusiness(yelpID: yelpID) }
        inflight[yelpID] = task
        defer { inflight[yelpID] = nil }

        let data = try await task.value
        if !data.isExpired {
            cache[yelpID] = data
            await YelpDiskCache.shared.storeBusiness(data)
        } else {
            cache[yelpID] = nil
        }
        if let placeID { yelpIDByPlaceID[placeID] = yelpID }
        return data
    }

    private func resolveYelpID(for place: Place) async -> String? {
        if let yelpID = place.yelpID {
            yelpIDByPlaceID[place.id] = yelpID
            return yelpID
        }
        if let cached = yelpIDByPlaceID[place.id] { return cached }
        if let task = idInflight[place.id] {
            return await task.value
        }

        let task = Task { () -> String? in
            guard let dto = try? await PlaceAPI.fetchPlaceDetails(placeID: place.id),
                  let resolved = Place(dto: dto) else {
                return nil
            }
            return resolved.yelpID
        }
        idInflight[place.id] = task

        let id = await task.value
        idInflight[place.id] = nil
        if let id {
            yelpIDByPlaceID[place.id] = id
        }
        return id
    }

    private func shouldThrottleRefresh(for yelpID: String) -> Bool {
        if let last = lastRefreshAttempt[yelpID],
           Date().timeIntervalSince(last) < refreshThrottle {
            return true
        }
        return false
    }

    private func markRefreshAttempt(for yelpID: String) {
        lastRefreshAttempt[yelpID] = Date()
    }
}

private struct FavoritesPanel: View {
    let favorites: [FavoritePlaceSnapshot]
    let sortOption: FavoritesSortOption
    let onSelect: (FavoritePlaceSnapshot) -> Void
    let onCollapse: () -> Void
    let onSortChange: (FavoritesSortOption) -> Void

    @State private var googleRatings: [String: GooglePlaceData] = [:]
    @State private var fetchTask: Task<Void, Never>?

    private let detailColor = Color.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Favorites")
                    .font(.headline.weight(.semibold))
                if !favorites.isEmpty {
                    Text("\(favorites.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(detailColor)
                }
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(8)
                        .background(Color(.systemBackground), in: Circle())
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
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
                                FavoriteRow(
                                    snapshot: snapshot,
                                    googleData: snapshot.googlePlaceID.flatMap { googleRatings[$0] }
                                )
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
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 9)
        .task(id: favorites.map(\.id)) {
            await fetchGoogleRatings()
        }
    }

    private func fetchGoogleRatings() async {
        // Pre-populate from cache for instant display
        for snapshot in favorites {
            guard let googleID = snapshot.googlePlaceID, !googleID.isEmpty else { continue }
            if googleRatings[googleID] == nil {
                if let cached = await GooglePlaceCache.shared.cachedDataByID(googleID) {
                    googleRatings[googleID] = cached
                }
            }
        }

        // Get favorites that have googlePlaceID but no stored rating
        let toFetch = favorites.filter { snapshot in
            guard let googleID = snapshot.googlePlaceID, !googleID.isEmpty else { return false }
            // Skip if we already have cached data
            if googleRatings[googleID] != nil { return false }
            // Fetch if no rating stored
            return snapshot.rating == nil
        }

        guard !toFetch.isEmpty else { return }

        // Fetch in parallel with concurrency limit (using cache for deduplication/TTL)
        await withTaskGroup(of: (String, GooglePlaceData?).self) { group in
            for snapshot in toFetch.prefix(10) { // Limit concurrent fetches
                guard let googleID = snapshot.googlePlaceID else { continue }
                group.addTask {
                    do {
                        let data = try await GooglePlaceCache.shared.fetchPlace(
                            googlePlaceID: googleID,
                            placeID: snapshot.id
                        )
                        return (googleID, data)
                    } catch {
                        return (googleID, nil)
                    }
                }
            }

            for await (googleID, data) in group {
                if let data {
                    await MainActor.run {
                        googleRatings[googleID] = data
                    }
                }
            }
        }
    }

    private func sortButton(for option: FavoritesSortOption) -> some View {
        let isSelected = option == sortOption
        return Button {
            onSortChange(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FavoritesCollapsedPill: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Favorites")
                    .font(.subheadline.weight(.semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(.systemBackground))
                        )
                }
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteRow: View {
    let snapshot: FavoritePlaceSnapshot
    let googleData: GooglePlaceData?

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

    // Prefer fetched Google rating, fall back to stored rating
    private var effectiveRating: Double? {
        googleData?.rating ?? snapshot.rating
    }

    private var effectiveRatingCount: Int? {
        googleData?.reviewCount ?? snapshot.ratingCount
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

                if let rating = effectiveRating, rating > 0 {
                    let count = effectiveRatingCount ?? 0
                    let ratingLabel = count == 1 ? "rating" : "ratings"
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", rating))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        if count > 0 {
                            Text("(\(count) \(ratingLabel))")
                        }
                    }
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
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct NewSpotsScreen: View {
    @EnvironmentObject private var favoritesStore: FavoritesStore
    let spots: [NewSpotEntry]
    let spotlight: NewSpotEntry?
    let userLocation: CLLocation?
    let topInset: CGFloat
    let onSelect: (Place) -> Void
    @State private var yelpData: [UUID: YelpBusinessData] = [:]
    @State private var isPreviouslyTrendingExpanded = false
    private let primarySpotLimit = 6
    private let useYelpPhotos = false

    private var validYelpData: [UUID: YelpBusinessData] {
        guard useYelpPhotos else { return [:] }
        return Dictionary(uniqueKeysWithValues: yelpData.filter { !$0.value.isExpired })
    }

    // Computed properties for stable array identity
    private var primaryEntries: [NewSpotEntry] {
        Array(spots.prefix(primarySpotLimit))
    }

    private var previousEntries: [NewSpotEntry] {
        Array(spots.dropFirst(primarySpotLimit))
    }

    var body: some View {
        let spotlightEntry = spotlight
        let availableYelpData = validYelpData
        let isLoading = spots.isEmpty
        let hasPrimary = !primaryEntries.isEmpty
        let hasPrevious = !previousEntries.isEmpty

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Loading state
                if isLoading {
                    ProgressView("Loading new trendy spots…")
                        .progressViewStyle(.circular)
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Primary spots card
                if hasPrimary && !isLoading {
                    NewSpotsCard(
                        title: "New Trending Spots",
                        spots: primaryEntries,
                        yelpData: availableYelpData,
                        onSelect: onSelect
                    )
                    .zIndex(0)
                }

                // Previously Trending section
                if hasPrevious && !isLoading {
                    VStack(spacing: 0) {
                        // UIKit-backed tappable header
                        UIKitTapView {
                            isPreviouslyTrendingExpanded.toggle()
                        } content: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.headline.weight(.semibold))
                                Text("Previously Trending")
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                Text("\(previousEntries.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                                Image(systemName: isPreviouslyTrendingExpanded ? "chevron.down" : "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(.secondarySystemGroupedBackground))
                        }

                        if isPreviouslyTrendingExpanded {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(previousEntries) { entry in
                                    if entry.id != previousEntries.first?.id {
                                        Divider().background(Color.black.opacity(0.06))
                                    }
                                    NewSpotRow(entry: entry, yelpData: availableYelpData[entry.id], onSelect: onSelect)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 18)
                            .background(Color(.secondarySystemGroupedBackground))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 18, y: 9)
                    .zIndex(1)
                }

                // Spotlight section
                if let hero = spotlightEntry, !isLoading {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text("Restaurant Spotlight")
                                .font(.headline.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.primary)

                        NewSpotHero(entry: hero, yelpData: availableYelpData[hero.id], onSelect: onSelect)
                        SpotlightSummary(entry: hero)
                    }
                }
            }
            .padding(.top, max(topInset - 16, 0))
            .padding(.bottom, 32)
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task(id: yelpTaskKey) {
            await loadYelpData(for: yelpLoadPlaces)
        }
        .task(id: googleTaskKey) {
            await prefetchGoogleThumbs(for: googleLoadPlaces)
        }
    }

    private var yelpTaskKey: [UUID] {
        useYelpPhotos ? yelpLoadPlaces.map(\.id) : []
    }

    private var yelpLoadPlaces: [Place] {
        // Always include all spots to avoid task key changes when expanding
        var candidates = spots.map(\.place)
        if let spotlight {
            candidates.append(spotlight.place)
        }
        var seen = Set<UUID>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private var googleTaskKey: [UUID] {
        googleLoadPlaces.map(\.id)
    }

    private var googleLoadPlaces: [Place] {
        yelpLoadPlaces
    }

    private func loadYelpData(for places: [Place]) async {
        guard useYelpPhotos else { return }
        let candidates = prioritizePlacesByDistance(places.filter { $0.isYelpBacked })
        guard !candidates.isEmpty else { return }

        let maxConcurrent = 4
        let priorityCount = min(6, candidates.count)
        let priority = Array(candidates.prefix(priorityCount))
        let remaining = Array(candidates.dropFirst(priorityCount))

        func refresh(_ place: Place) {
            Task {
                if let refreshed = try? await YelpBusinessCache.shared.fetchBusiness(for: place, forceRefresh: true) {
                    await MainActor.run {
                        yelpData[place.id] = refreshed
                    }
                }
            }
        }

        func resolve(_ place: Place) async {
            if Task.isCancelled { return }

            if let existing = await MainActor.run(body: { yelpData[place.id] }) {
                if existing.isExpired {
                    await MainActor.run {
                        yelpData[place.id] = nil
                    }
                } else {
                    if existing.isNearExpiry {
                        refresh(place)
                    }
                    return
                }
            }

            if let cached = await YelpBusinessCache.shared.cachedData(for: place) {
                await MainActor.run {
                    yelpData[place.id] = cached
                }
                if cached.isNearExpiry {
                    refresh(place)
                }
                return
            }

            do {
                let data = try await YelpBusinessCache.shared.fetchBusiness(for: place)
                await MainActor.run {
                    yelpData[place.id] = data
                }
            } catch {
                // ignore list failures
            }
        }

        for place in priority {
            await resolve(place)
        }

        guard !remaining.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = remaining.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let next = iterator.next() else { break }
                group.addTask { await resolve(next) }
            }

            while await group.next() != nil {
                if Task.isCancelled { break }
                if let next = iterator.next() {
                    group.addTask { await resolve(next) }
                }
            }
        }
    }

    private func prefetchGoogleThumbs(for places: [Place]) async {
        let candidates = prioritizePlacesByDistance(places)
        guard !candidates.isEmpty else { return }

        let priorityCount = min(6, candidates.count)
        for place in candidates.prefix(priorityCount) {
            GooglePlaceThumb.prefetch(for: place)
        }

        let remaining = candidates.dropFirst(priorityCount)
        guard !remaining.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 800_000_000)
        for place in remaining.prefix(24) {
            GooglePlaceThumb.prefetch(for: place)
        }
    }

    private func prioritizePlacesByDistance(_ places: [Place]) -> [Place] {
        guard let userLocation else { return places }
        return places.sorted { lhs, rhs in
            let lhsDist = CLLocation(latitude: lhs.coordinate.latitude,
                                     longitude: lhs.coordinate.longitude)
                .distance(from: userLocation)
            let rhsDist = CLLocation(latitude: rhs.coordinate.latitude,
                                     longitude: rhs.coordinate.longitude)
                .distance(from: userLocation)
            return lhsDist < rhsDist
        }
    }

    private struct NewSpotsCard: View {
        let title: String
        let spots: [NewSpotEntry]
        let yelpData: [UUID: YelpBusinessData]
        let onSelect: (Place) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Color.primary)

                NewSpotListView(spots: spots, yelpData: yelpData, onSelect: onSelect)
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .allowsHitTesting(false)
            }
            // Shadow temporarily removed to test if it affects gesture recognition
        }
    }

}

// MARK: - UIKit Tap Wrapper (bypasses SwiftUI gesture bugs)

private struct UIKitTapView<Content: View>: UIViewRepresentable {
    let action: () -> Void
    let content: () -> Content

    func makeUIView(context: Context) -> UIKitTapContainerView<Content> {
        let container = UIKitTapContainerView(content: content(), action: action)
        return container
    }

    func updateUIView(_ uiView: UIKitTapContainerView<Content>, context: Context) {
        uiView.updateContent(content())
    }
}

private class UIKitTapContainerView<Content: View>: UIView {
    private var hostingController: UIHostingController<Content>
    private let action: () -> Void

    init(content: Content, action: @escaping () -> Void) {
        self.action = action
        self.hostingController = UIHostingController(rootView: content)
        super.init(frame: .zero)

        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateContent(_ content: Content) {
        hostingController.rootView = content
    }

    @objc private func handleTap() {
        action()
    }

    override var intrinsicContentSize: CGSize {
        hostingController.view.intrinsicContentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        hostingController.view.sizeThatFits(size)
    }
}

// MARK: - New Spots List

private struct NewSpotListView: View {
    let spots: [NewSpotEntry]
    let yelpData: [UUID: YelpBusinessData]
    let onSelect: (Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                if index != 0 {
                    Divider()
                        .background(Color.black.opacity(0.06))
                }
                NewSpotRow(entry: spot, yelpData: yelpData[spot.id], onSelect: onSelect)
            }
        }
    }
}

private struct NewSpotImageView: View {
    let image: NewSpotImage
    let place: Place?
    let overrideURL: URL?
    private let useYelpOverride = false
    private let useLegacyThumbs = false

    var body: some View {
        if useYelpOverride, let overrideURL {
            CachedAsyncImage(url: overrideURL) {
                fallbackImage
            } failure: {
                fallbackImage
            }
            .scaledToFill()
        } else if let place {
            if useLegacyThumbs {
                ZStack {
                    TopRatedPhotoThumb(placeID: place.id, showsPlaceholder: false)
                    NewSpotGoogleThumb(place: place)
                }
            } else {
                NewSpotGoogleThumb(place: place)
            }
        } else {
            fallbackImage
        }
    }

        private var placeholder: some View {
            Color.gray.opacity(0.3)
        }

        @ViewBuilder
        private var fallbackImage: some View {
            switch image {
            case .remote(let url):
                CachedAsyncImage(url: url) {
                    placeholder
                } failure: {
                    placeholder
                }
                .scaledToFill()
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
        }
}

private struct NewSpotGoogleThumb: View {
        let place: Place
        @State private var imageURL: URL?
        @State private var refreshToken: Int = 0

        var body: some View {
            Group {
                if let url = imageURL {
                    CachedAsyncImage(url: url) {
                        Color.clear
                    } failure: {
                        Color.clear
                    }
                    .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .task(id: loadToken) {
                await loadImage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .placePhotoCacheDidUpdate)) { notice in
                guard let placeID = notice.userInfo?["placeID"] as? UUID else { return }
                guard placeID == place.id else { return }
                refreshToken &+= 1
            }
        }

        private var loadToken: String {
            "\(place.id.uuidString)-\(refreshToken)"
        }

        private func loadImage() async {
            if let cached = await PlacePhotoCache.shared.get(place.id),
               let first = cached.first(where: { $0.isGooglePhoto }),
               let url = URL(string: first.imageUrl) {
                await MainActor.run {
                    imageURL = GoogleThumbURLBuilder.thumbnailURL(from: url)
                }
                return
            }
            if let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
                await MainActor.run {
                    imageURL = url
                }
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if imageURL == nil, let url = await GooglePhotoResolver.shared.fetchThumbnailURL(for: place) {
                await MainActor.run {
                    imageURL = url
                }
            }
        }
    }

private struct NewSpotRow: View {
        @EnvironmentObject private var favoritesStore: FavoritesStore
        let entry: NewSpotEntry
        let yelpData: YelpBusinessData?
        let onSelect: (Place) -> Void

        private var place: Place { entry.place }

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    onSelect(place)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        NewSpotImageView(image: entry.image, place: place, overrideURL: yelpPhotoURL)
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

                            if place.displayRating != nil {
                                ratingView(for: place)
                            }

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

                        Color.clear
                            .frame(width: 28, height: 28)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                DateOpenedLabel(month: entry.openedOn.month, day: entry.openedOn.day)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
            .overlay(alignment: .topTrailing) {
                FavoriteToggleSmall(place: place)
            }
        }

        private func ratingView(for place: Place) -> some View {
            let count = place.displayRatingCount ?? 0
            let hasReviews = count > 0
            return HStack(spacing: 4) {
                Image(systemName: hasReviews ? "star.fill" : "star")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasReviews ? Color.orange : Color.secondary)
                if hasReviews, let rating = place.displayRating {
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                    Text("(\(reviewLabel(for: count)))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                } else {
                    Text("No reviews yet")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .italic()
                }
            }
        }

        private func reviewLabel(for count: Int?) -> String {
            guard let count, count > 0 else { return "No reviews yet" }
            if count == 1 { return "1 review" }
            if count >= 1000 { return String(format: "%.1fk reviews", Double(count) / 1000.0) }
            return "\(count) reviews"
        }

        private var yelpPhotoURL: URL? {
            guard let urlString = yelpData?.photos.first?.url else { return nil }
            guard let url = URL(string: urlString) else { return nil }
            return TopRatedPhotoThumb.optimizedURL(from: url)
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
                let currentlyFavorite = isFavorite
                Haptics.favoriteToggled(isNowFavorite: !currentlyFavorite)
                favoritesStore.toggleFavorite(
                    for: place,
                    name: place.name,
                    address: place.address,
                    rating: place.rating,
                    ratingCount: place.ratingCount,
                    source: place.source,
                    sourceID: place.sourceID,
                    externalID: place.externalID,
                    applePlaceID: place.applePlaceID,
                    googlePlaceID: place.googlePlaceID
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
        let yelpData: YelpBusinessData?
        let onSelect: (Place) -> Void

        var body: some View {
            Button {
                onSelect(entry.place)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    NewSpotImageView(image: entry.image, place: entry.place, overrideURL: yelpPhotoURL)
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

        private var yelpPhotoURL: URL? {
            guard let urlString = yelpData?.photos.first?.url else { return nil }
            guard let url = URL(string: urlString) else { return nil }
            return TopRatedPhotoThumb.optimizedURL(from: url)
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
        VStack(spacing: 4) {
            Text("OPENED")
                .font(.system(size: 8, weight: .heavy, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(Color.secondary)
                .frame(width: 30)
                .accessibilityHidden(true)

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
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .frame(width: 30)
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

struct PlaceDetailView: View {
    let place: Place

    private static let appleDetailsEnabled = false

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
            let loadedDetails = Self.appleDetailsEnabled ? appleLoadedDetails : nil

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        if !viewModel.photos.isEmpty {
                            PhotoCarouselView(
                                photos: viewModel.photos,
                                yelpAttributionURL: yelpAttributionURL
                            ) { index, _ in
                                expandedPhotoSelection = PhotoSelection(index: index)
                            }
                        }
                        // Order: photos → halal details → rating (non-Apple path)
                        halalSection
                        if let ratingModel, !hasAppleDetails {
                            YelpRatingRow(model: ratingModel, style: .prominent)
                        }
                        Divider().opacity(0.4)
                        if Self.appleDetailsEnabled {
                            appleStatusSection
                        } else {
                            googleDetailsSection
                        }
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
                initialIndex: selection.index,
                yelpURL: yelpAttributionURL
            ) {
                expandedPhotoSelection = nil
            }
        }
        .task(id: place.id) {
            await viewModel.load(place: place, includeAppleDetails: Self.appleDetailsEnabled)
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
        .onChange(of: expandedPhotoSelection) { _, newValue in
            if let selection = newValue,
               !viewModel.photos.indices.contains(selection.index) {
                expandedPhotoSelection = nil
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.red : Color.white)
                .offset(y: 0.5)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4.5, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func toggleFavorite() {
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        let currentPlace = viewModel.resolvedPlace ?? place
        // Prefer Google rating if available, otherwise fall back to place rating
        let effectiveRating = viewModel.googleData?.rating ?? currentPlace.rating
        let effectiveRatingCount = viewModel.googleData?.reviewCount ?? currentPlace.ratingCount
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            let currentlyFavorite = isFavorite
            Haptics.favoriteToggled(isNowFavorite: !currentlyFavorite)
            favoritesStore.toggleFavorite(
                for: currentPlace,
                name: displayName,
                address: displayAddress,
                rating: effectiveRating,
                ratingCount: effectiveRatingCount,
                source: currentPlace.source,
                sourceID: currentPlace.sourceID,
                externalID: currentPlace.externalID,
                applePlaceID: appleID,
                googlePlaceID: currentPlace.googlePlaceID
            )
        }
    }

    private func refreshFavoriteSnapshot() {
        guard favoritesStore.contains(id: place.id) else { return }
        let appleID = appleLoadedDetails?.applePlaceID ?? place.applePlaceID
        let currentPlace = viewModel.resolvedPlace ?? place
        // Prefer Google rating if available
        let effectiveRating = viewModel.googleData?.rating ?? currentPlace.rating
        let effectiveRatingCount = viewModel.googleData?.reviewCount ?? currentPlace.ratingCount
        favoritesStore.updateFavoriteIfNeeded(
            for: currentPlace,
            name: displayName,
            address: displayAddress,
            rating: effectiveRating,
            ratingCount: effectiveRatingCount,
            source: currentPlace.source,
            sourceID: currentPlace.sourceID,
            externalID: currentPlace.externalID,
            applePlaceID: appleID,
            googlePlaceID: currentPlace.googlePlaceID
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Rating moved below photos to follow: photos → rating → halal details.
        }
    }

    @ViewBuilder
    private var halalSection: some View {
        if halalDetailsDisplay != nil {
            VStack(alignment: .leading, spacing: 8) {
                partialHalalMessageView()
            }
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

    private var googleDetailsSection: some View {
        GooglePlaceDetailView(
            place: viewModel.resolvedPlace ?? place,
            googleData: viewModel.googleData,
            googleErrorMessage: viewModel.googleErrorMessage
        )
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                if !viewModel.photos.isEmpty {
                    PhotoCarouselView(
                        photos: viewModel.photos,
                        yelpAttributionURL: yelpAttributionURL
                    ) { index, _ in
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 20)
            .frame(minHeight: availableHeight, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private var displayName: String {
        if case let .loaded(details) = viewModel.loadingState, !details.displayName.isEmpty {
            return details.displayName
        }
        return place.name
    }

    private var yelpAttributionURL: URL? {
        if let urlString = viewModel.yelpData?.yelpURL,
           let url = URL(string: urlString) {
            return url
        }
        if let yelpID = viewModel.yelpData?.yelpID,
           let encoded = yelpID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://www.yelp.com/biz/\(encoded)") {
            return url
        }
        let currentPlace = viewModel.resolvedPlace ?? place
        if let yelpID = currentPlace.yelpID,
           let encoded = yelpID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://www.yelp.com/biz/\(encoded)") {
            return url
        }
        return nil
    }

    private var ratingSourceLabel: String? {
        let currentPlace = viewModel.resolvedPlace ?? place
        if currentPlace.isYelpBacked { return "Yelp" }
        guard let raw = currentPlace.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return readableSource(raw)
    }

    private var ratingModel: RatingDisplayModel? {
        let currentPlace = viewModel.resolvedPlace ?? place
        if let googleData = viewModel.googleData,
           let rating = googleData.rating,
           rating > 0 {
            return RatingDisplayModel(
                rating: rating,
                reviewCount: googleData.reviewCount,
                source: "Google",
                sourceURL: googleData.mapsURL.flatMap(URL.init(string:))
            )
        }
        if currentPlace.isYelpBacked {
            guard let yelpData = viewModel.yelpData,
                  let rating = yelpData.rating,
                  rating > 0 else { return nil }
            return RatingDisplayModel(
                rating: rating,
                reviewCount: yelpData.reviewCount,
                source: "Yelp",
                sourceURL: yelpData.yelpURL.flatMap(URL.init(string:))
            )
        }

        guard let rating = currentPlace.rating, rating > 0 else { return nil }
        return RatingDisplayModel(
            rating: rating,
            reviewCount: currentPlace.ratingCount,
            source: ratingSourceLabel,
            sourceURL: nil
        )
    }

    private var displayAddress: String? {
        if let formatted = viewModel.googleData?.formattedAddress,
           !formatted.isEmpty {
            return formatted
        }
        if case let .loaded(details) = viewModel.loadingState {
            if let short = details.shortAddress, !short.isEmpty {
                return short
            }
            if let full = details.fullAddress, !full.isEmpty {
                return full
            }
        }
        let stored = (viewModel.resolvedPlace ?? place).address
        if let stored, !stored.isEmpty { return stored }
        return place.displayLocation
    }

    private var hasAppleDetails: Bool {
        guard Self.appleDetailsEnabled else { return false }
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
                status: display.status,
                servesAlcohol: place.servesAlcohol,
                certifierOrg: display.certifierOrg
            )
            .overlay(alignment: .topTrailing) {
                if !hasAppleDetails {
                    favoriteButton
                        .padding(12)
                }
            }
            .transition(AnyTransition.opacity)
        } else if !hasAppleDetails {
            favoriteButton
        }
    }

    private var halalDetailsDisplay: HalalDetailsDisplay? {
        let currentPlace = viewModel.resolvedPlace ?? place
        // Show details card for both partial (yes) and fully halal (only)
        switch currentPlace.halalStatus {
        case .yes:
            let reminder = "Please always double check with restaurant."
            let trimmed = currentPlace.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return HalalDetailsDisplay(status: .partial, note: note, reminder: reminder, certifierOrg: currentPlace.certifierOrg)
        case .only:
            let reminder = "Please always double check with restaurant."
            let trimmed = currentPlace.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return HalalDetailsDisplay(status: .full, note: note, reminder: reminder, certifierOrg: currentPlace.certifierOrg)
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
    let certifierOrg: String?
}

private struct HalalDetailsCard: View {
    let headline: String
    let note: String?
    let reminder: String
    let status: HalalUIStatus
    let servesAlcohol: Bool?
    let certifierOrg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headline)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)
            }

            HalalDetailRow(
                iconName: status == .full ? "Full Halal" : "Partial Halal",
                text: status == .full ? "Full halal menu" : "Partial halal menu",
                certifierOrg: certifierOrg
            )

            if let servesAlcohol {
                HalalDetailRow(
                    iconName: servesAlcohol ? "Yes Alcohol" : "No Alcohol",
                    text: servesAlcohol ? "Alcohol served" : "No alcohol served",
                    certifierOrg: nil
                )
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

private struct HalalDetailRow: View {
    let iconName: String
    let text: String
    let certifierOrg: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(iconName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.primary)

                    if let certifier = certifierOrg {
                        CertifierBadge(certifier: certifier)
                    }
                }
            }
        }
    }
}

private struct CertifierBadge: View {
    let certifier: String
    @State private var showingInfo = false

    private var displayText: String {
        "\(certifier) Certified"
    }

    private var certifierInfo: CertifierInfo {
        CertifierInfo.info(for: certifier)
    }

    var body: some View {
        Button {
            showingInfo = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(badgeColor)

                Text(displayText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(badgeColor)

                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(badgeColor.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(badgeColor.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingInfo) {
            CertifierInfoSheet(info: certifierInfo)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
    }

    private var badgeColor: Color { Color(red: 0.13, green: 0.55, blue: 0.45) }
}

private struct CertifierInfo {
    let code: String
    let fullName: String
    let description: String

    static func info(for code: String) -> CertifierInfo {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "HMS":
            return CertifierInfo(
                code: "HMS",
                fullName: "Halal Monitoring Services",
                description: "HMS (Halal Monitoring Services) monitors and certifies that meat is hand-slaughtered according to the principles of Zabiha Halal."
            )
        case "SBNY":
            return CertifierInfo(
                code: "SBNY",
                fullName: "Shar'i Board of New York",
                description: "SBNY (Shar'i Board of New York) is a halal certification organization that ensures food establishments comply with Islamic dietary laws and Zabiha standards."
            )
        case "HFSAA":
            return CertifierInfo(
                code: "HFSAA",
                fullName: "Halal Food Standards Alliance of America",
                description: "HFSAA (Halal Food Standards Alliance of America) certifies food products and establishments to meet authentic halal standards based on Islamic guidelines."
            )
        case "ISNA":
            return CertifierInfo(
                code: "ISNA",
                fullName: "Islamic Services of America",
                description: "ISA (Islamic Services of America, formerly ISNA Halal) provides halal certification ensuring products meet Islamic dietary requirements."
            )
        case "HFA":
            return CertifierInfo(
                code: "HFA",
                fullName: "Halal Food Authority",
                description: "HFA (Halal Food Authority) is a certification body that monitors and certifies halal food products and establishments."
            )
        default:
            return CertifierInfo(
                code: code,
                fullName: code,
                description: "This establishment has been certified halal by \(code)."
            )
        }
    }
}

private struct CertifierInfoSheet: View {
    let info: CertifierInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(badgeColor)

                VStack(spacing: 6) {
                    Text(info.fullName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    Text(info.code)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.secondary)
                }

                Text(info.description)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var badgeColor: Color { Color(red: 0.13, green: 0.55, blue: 0.45) }
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
        guard Self.appleDetailsEnabled else { return nil }
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

private enum PhotoAttribution {
    case yelp(URL?)
    case text(String)
}

private struct PhotoAttributionOverlay: View {
    let attribution: PhotoAttribution

    var body: some View {
        switch attribution {
        case .yelp(let url):
            let mark = YelpLogoMark(style: .overlay)
            if let url {
                Link(destination: url) { mark }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Yelp")
            } else {
                mark
                    .accessibilityLabel("Yelp")
            }
        case .text(let label):
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(label)
        }
    }
}

private struct FullscreenPhotoView: View {
    let photos: [PlacePhoto]
    let yelpURL: URL?
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(photos: [PlacePhoto], initialIndex: Int, yelpURL: URL?, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.yelpURL = yelpURL
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
                                    let displayURL = photo.isGooglePhoto
                                        ? GooglePhotoURLBuilder.fullSizeURL(from: url)
                                        : url
                                    ZoomableCachedImage(url: displayURL, resetID: photo.id) {
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
            if let attribution = currentAttribution {
                PhotoAttributionOverlay(attribution: attribution)
                    .padding(16)
                    .offset(y: dragOffset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded restaurant photo")
        .accessibilityAddTraits(.isModal)
        .gesture(dismissDragGesture)
        .onChange(of: photos.count) { _, _ in
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

    private var currentAttribution: PhotoAttribution? {
        guard photos.indices.contains(currentIndex) else { return nil }
        let photo = photos[currentIndex]
        if photo.isYelpPhoto { return .yelp(yelpURL) }
        if let label = photo.attributionLabel { return .text("Photo credit: \(label)") }
        return nil
    }
}

nonisolated private enum PlacePhotoURLBuilder {
    private static let supabaseObjectPrefix = "/storage/v1/object/public/"
    private static let supabaseRenderPrefix = "/storage/v1/render/image/public/"
    private static let thumbnailWidth = 1600
    private static let thumbnailQuality = "85"

    static func thumbnailURL(from original: URL) -> URL {
        if let supabase = supabaseThumbnailURL(from: original,
                                               width: thumbnailWidth,
                                               quality: thumbnailQuality) {
            return supabase
        }
        return original
    }

    private static func supabaseThumbnailURL(from original: URL,
                                             width: Int,
                                             quality: String) -> URL? {
        guard let baseURL = Env.optionalURL(),
              let baseHost = baseURL.host,
              original.host == baseHost else { return nil }

        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme
        components?.host = baseHost
        if let path = components?.path {
            if path.contains(supabaseObjectPrefix) {
                components?.path = path.replacingOccurrences(of: supabaseObjectPrefix,
                                                            with: supabaseRenderPrefix)
            } else if !path.contains(supabaseRenderPrefix) {
                return nil
            }
        }
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "width" || $0.name == "quality" }
        items.append(URLQueryItem(name: "width", value: "\(width)"))
        items.append(URLQueryItem(name: "quality", value: quality))
        components?.queryItems = items
        return components?.url
    }
}

nonisolated private extension PlacePhoto {
    var isYelpPhoto: Bool {
        src.lowercased().contains("yelp") ||
        (attribution?.lowercased().contains("yelp") ?? false) ||
        imageUrl.lowercased().contains("yelp")
    }

    var isGooglePhoto: Bool {
        src.lowercased().contains("google") ||
        (attribution?.lowercased().contains("google") ?? false) ||
        (externalId?.lowercased().hasPrefix("google:") ?? false) ||
        imageUrl.lowercased().contains("google")
    }

    var attributionLabel: String? {
        if let trimmed = attribution?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
        if isGooglePhoto { return "Google" }
        return nil
    }

    var compactAttributionLabel: String? {
        if isGooglePhoto { return "© Google" }
        return attributionLabel
    }
}

private actor PhotoPrefetcher {
    static let shared = PhotoPrefetcher()
    private var warmed: Set<URL> = []

    func prefetch(_ url: URL) async {
        if warmed.contains(url) { return }
        warmed.insert(url)
        await YelpImagePolicy.warm(url)
    }
}

private struct PhotoCarouselView: View {
    let photos: [PlacePhoto]
    let yelpAttributionURL: URL?
    let onPhotoSelected: (Int, PlacePhoto) -> Void

    @State private var selectedIndex = 0
    private var thumbnailMaxPixelSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let base = max(screenWidth, 220)
        return base * UIScreen.main.scale
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { pair in
                let index = pair.offset
                let photo = pair.element
                ZStack(alignment: .bottomTrailing) {
                    if let url = URL(string: photo.imageUrl) {
                        let thumbnailURL = photo.isGooglePhoto
                            ? GooglePhotoURLBuilder.thumbnailURL(from: url)
                            : PlacePhotoURLBuilder.thumbnailURL(from: url)
                        let cacheKey = "thumb:\(thumbnailURL.absoluteString)"
                        CachedAsyncImage(url: thumbnailURL,
                                         cacheKey: cacheKey,
                                         maxPixelSize: thumbnailMaxPixelSize) {
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
        .overlay(alignment: .bottomTrailing) {
            if let attribution = currentAttribution {
                PhotoAttributionOverlay(attribution: attribution)
                    .padding(16)
            }
        }
        .onChange(of: photos) { _, newValue in
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
        .task(id: selectedIndex) {
            await prefetchSelectedFullSize()
        }
        .task(id: photos.count) {
            await prefetchSelectedFullSize()
        }
    }

    private func prefetchSelectedFullSize() async {
        guard photos.indices.contains(selectedIndex) else { return }
        let indices = [selectedIndex, selectedIndex + 1]
            .filter { photos.indices.contains($0) }
        for index in indices {
            guard let url = URL(string: photos[index].imageUrl) else { continue }
            let fullURL = photos[index].isGooglePhoto
                ? GooglePhotoURLBuilder.fullSizeURL(from: url)
                : url
            await PhotoPrefetcher.shared.prefetch(fullURL)
        }
    }

    private var currentAttribution: PhotoAttribution? {
        guard photos.indices.contains(selectedIndex) else { return nil }
        let photo = photos[selectedIndex]
        if photo.isYelpPhoto { return .yelp(yelpAttributionURL) }
        if let label = photo.compactAttributionLabel { return .text(label) }
        return nil
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
        lhs.isApproximatelyEqual(to: rhs)
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
    @Published private(set) var resolvedPlace: Place?
    @Published private(set) var googleData: GooglePlaceData?
    @Published private(set) var googleErrorMessage: String?
    @Published private(set) var yelpData: YelpBusinessData?
    @Published private(set) var yelpErrorMessage: String?

    private let service: ApplePlaceDetailService
    private var lastSuccessfulPlaceID: UUID?

    init(service: ApplePlaceDetailService? = nil) {
        if let service {
            self.service = service
        } else {
            self.service = ApplePlaceDetailService.shared
        }
    }

    func load(place: Place, includeAppleDetails: Bool) async {
        if resolvedPlace?.id != place.id {
            resolvedPlace = place
            photos = []
            googleData = nil
            googleErrorMessage = nil
            yelpData = nil
            yelpErrorMessage = nil
        }

        if case .loaded = loadingState,
           lastSuccessfulPlaceID == place.id {
            return
        }

        if place.certifierOrg == nil {
            Task { [weak self] in
                await self?.refreshSupabasePlace(for: place)
            }
        }

        guard includeAppleDetails else {
            loadingState = .idle
            lastSuccessfulPlaceID = nil
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

    private func refreshSupabasePlace(for place: Place) async {
        do {
            guard let dto = try await PlaceAPI.fetchPlaceDetails(placeID: place.id),
                  let updated = Place(dto: dto) else { return }
            guard resolvedPlace?.id == place.id else { return }
            resolvedPlace = updated
        } catch {
#if DEBUG
            print("[PlaceDetailViewModel] Supabase place refresh failed:", error)
#endif
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

    func loadGoogleData(for place: Place) async {
        if let current = googleData, current.isExpired {
            googleData = nil
        }

        if let cached = await GooglePlaceCache.shared.cachedData(for: place) {
            googleData = cached
            googleErrorMessage = nil
            if cached.isNearExpiry {
                refreshGoogleData(for: place)
            }
            return
        }

        do {
            let data = try await GooglePlaceCache.shared.fetchPlace(for: place)
            googleData = data
            googleErrorMessage = nil
        } catch GooglePlaceCacheError.missingGooglePlaceID {
            googleData = nil
            googleErrorMessage = nil
        } catch {
            googleData = nil
            googleErrorMessage = error.localizedDescription
#if DEBUG
            print("[GooglePlacesAPI] Failed to fetch Google data:", error)
#endif
        }
    }

    private func refreshGoogleData(for place: Place) {
        let placeID = place.id
        Task { [weak self] in
            guard let self else { return }
            guard let refreshed = try? await GooglePlaceCache.shared.fetchPlace(
                for: place,
                forceRefresh: true
            ) else { return }
            let googlePhotos = refreshed.photos
                .filter { !BlockedGooglePhotos.isBlocked(url: $0.url, reference: $0.reference) }
                .map { photo in
                    let externalId = photo.reference.map { "google:\($0)" } ?? "google:\(photo.position)"
                    return PlacePhoto(
                        placeID: placeID,
                        position: photo.position,
                        url: photo.url,
                        attribution: photo.attribution,
                        source: "google",
                        externalId: externalId,
                        width: photo.width,
                        height: photo.height
                    )
                }
            await MainActor.run {
                guard self.resolvedPlace?.id == placeID else { return }
                self.googleData = refreshed
                self.googleErrorMessage = nil
                self.photos = googlePhotos
            }
            await PlacePhotoCache.shared.set(
                placeID,
                photos: googlePhotos,
                expiresAt: refreshed.effectiveExpiresAt
            )
        }
    }

    func loadYelpData(for place: Place) async {
        guard place.isYelpBacked else {
            yelpData = nil
            return
        }

        if let current = yelpData, current.isExpired {
            yelpData = nil
        }

        if let cached = await YelpBusinessCache.shared.cachedData(for: place) {
            yelpData = cached
            yelpErrorMessage = nil
            if cached.isNearExpiry {
                refreshYelpData(for: place)
            }
            return
        }

        do {
            let data = try await YelpBusinessCache.shared.fetchBusiness(for: place)
            yelpData = data
            yelpErrorMessage = nil
        } catch {
            yelpData = nil
            yelpErrorMessage = error.localizedDescription
#if DEBUG
            print("[YelpAPI] Failed to fetch Yelp data:", error)
#endif
        }
    }

    private func refreshYelpData(for place: Place) {
        let placeID = place.id
        Task { [weak self] in
            guard let self else { return }
            guard let refreshed = try? await YelpBusinessCache.shared.fetchBusiness(
                for: place,
                forceRefresh: true
            ) else { return }
            let yelpPhotos = refreshed.photos.map { photo in
                PlacePhoto(
                    placeID: placeID,
                    position: photo.position,
                    url: photo.url,
                    attribution: photo.attribution
                )
            }
            await MainActor.run {
                guard self.resolvedPlace?.id == placeID else { return }
                self.yelpData = refreshed
                self.yelpErrorMessage = nil
                self.photos = yelpPhotos
            }
            await PlacePhotoCache.shared.set(
                placeID,
                photos: yelpPhotos,
                expiresAt: refreshed.effectiveExpiresAt
            )
        }
    }

    func loadPhotos(for place: Place) async {
        do {
            if let cached = await PlacePhotoCache.shared.get(place.id) {
                if cached.contains(where: { $0.isGooglePhoto }) {
                    self.photos = cached
                }
            }

            await loadGoogleData(for: place)
            if let googleData {
                let googlePhotos = googleData.photos
                    .filter { !BlockedGooglePhotos.isBlocked(url: $0.url, reference: $0.reference) }
                    .map { photo in
                        let externalId = photo.reference.map { "google:\($0)" } ?? "google:\(photo.position)"
                        return PlacePhoto(
                            placeID: place.id,
                            position: photo.position,
                            url: photo.url,
                            attribution: photo.attribution,
                            source: "google",
                            externalId: externalId,
                            width: photo.width,
                            height: photo.height
                        )
                    }
                self.photos = googlePhotos
                await PlacePhotoCache.shared.set(
                    place.id,
                    photos: googlePhotos,
                    expiresAt: googleData.effectiveExpiresAt
                )
                return
            } else {
                googleData = nil
            }

            if place.isYelpBacked {
                if let cached = await PlacePhotoCache.shared.get(place.id) {
                    if cached.contains(where: { $0.isYelpPhoto }) {
                        self.photos = cached
                    }
                }
                await loadYelpData(for: place)
                if let yelpData {
                    let yelpPhotos = yelpData.photos.map { photo in
                        PlacePhoto(placeID: place.id,
                                   position: photo.position,
                                   url: photo.url,
                                   attribution: photo.attribution)
                    }
                    self.photos = yelpPhotos
                    await PlacePhotoCache.shared.set(
                        place.id,
                        photos: yelpPhotos,
                        expiresAt: yelpData.effectiveExpiresAt
                    )
                } else if self.photos.isEmpty {
                    self.photos = []
                }
                return
            } else {
                yelpData = nil
            }

            if let cached = await PlacePhotoCache.shared.get(place.id) {
                self.photos = cached
                return
            }
            guard let supabaseURL = Env.optionalURL(),
                  let anonKey = Env.optionalAnonKey() else { return }
            guard var comps = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else { return }
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
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
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
    @Published private(set) var globalDatasetVersion: Int = 0
    @Published fileprivate private(set) var persistedCommunityTopRated: [TopRatedRegion: [Place]] = [:]

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
    private var manualOverlayTask: Task<Void, Never>?
    private var globalDatasetBootstrapTask: Task<Void, Never>?
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
    private var lastPersistedSnapshotSignature: Int?
    private var pendingPersistSnapshotSignature: Int?
    private let persistDebounceNanoseconds: UInt64 = 1_500_000_000
    private let diskSnapshotStalenessInterval: TimeInterval = 60 * 60 * 6
    private var globalDatasetETag: String?
    private var googleCandidateCacheSignature: Int?
    private var googleCandidatesAllCache: [Place] = []

    func place(with id: UUID) -> Place? {
        let candidates = [
            places.first(where: { $0.id == id }),
            searchResults.first(where: { $0.id == id }),
            allPlaces.first(where: { $0.id == id }),
            globalDataset.first(where: { $0.id == id })
        ].compactMap { $0 }

        return pickBestPlace(from: candidates)
    }

    private func pickBestPlace(from candidates: [Place]) -> Place? {
        guard var best = candidates.first else { return nil }
        var bestScore = placeScore(best)
        for candidate in candidates.dropFirst() {
            let score = placeScore(candidate)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    private func placeScore(_ place: Place) -> Int {
        var score = 0
        if place.hasGooglePlaceID { score += 4 }
        if let mapsURL = place.googleMapsURL, !mapsURL.isEmpty { score += 2 }
        if let externalID = place.externalID, !externalID.isEmpty { score += 1 }
        if let address = place.address, !address.isEmpty { score += 1 }
        if let displayLocation = place.displayLocation, !displayLocation.isEmpty { score += 1 }
        return score
    }

    func fetchPlaceDetails(for id: UUID) async -> Place? {
        if let existing = place(with: id) { return existing }

        do {
            guard let dto = try await PlaceAPI.fetchPlaceDetails(placeID: id),
                  let place = Place(dto: dto),
                  isTrustedPlace(place) else {
                return nil
            }

            insertOrUpdatePlace(place)
            mergeIntoGlobalDataset([place], persist: false)
            refreshSearchResultsIfNeeded(with: place)
            return place
        } catch {
            errorMessage = Self.message(for: error)
            presentingError = true
            return nil
        }
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
        let fetchLimit = dynamicResultLimit(for: requestRegion)
        let fetchMetadata: String
#if DEBUG
        let centerLat = String(format: "%.4f", requestRegion.center.latitude)
        let centerLon = String(format: "%.4f", requestRegion.center.longitude)
        let spanLat = String(format: "%.4f", requestRegion.span.latitudeDelta)
        let spanLon = String(format: "%.4f", requestRegion.span.longitudeDelta)
        fetchMetadata = "center=(\(centerLat),\(centerLon)) span=(\(spanLat)x\(spanLon)) filter=\(filter) eager=\(eager) limit=\(fetchLimit)"
#else
        fetchMetadata = ""
#endif
        manualOverlayTask?.cancel()
        manualOverlayTask = nil
        let cacheHit = cache.value(for: requestRegion)
        let cachedOverride = cacheHit.map {
            PlaceOverrides
                .apply(overridesTo: $0.places, in: requestRegion)
                .filter(self.isTrustedPlace(_:))
        }
        let hasFreshCache = (cacheHit?.isFresh ?? false)
        var satisfiedFromGlobalDataset = false

        if let cachedPlaces = cachedOverride {
            // Show cached results immediately; subsequent checks decide whether a refresh is needed.
            allPlaces = cachedPlaces
            apply(filter: filter)
        } else if let preliminary = globalDatasetSlice(for: requestRegion, limit: fetchLimit), !preliminary.isEmpty {
            allPlaces = preliminary
            apply(filter: filter)
            if !eager {
                cache.store(preliminary, region: requestRegion)
                satisfiedFromGlobalDataset = true
            }
        }

        let hasFreshData = hasFreshCache || satisfiedFromGlobalDataset

        if let last = lastRequestedRegion,
           regionIsSimilar(lhs: last, rhs: requestRegion),
           hasFreshData,
           !eager {
#if DEBUG
            PerformanceMetrics.point(event: .mapFetch, metadata: "Skipped – similar region \(fetchMetadata)")
#endif
            fetchTask?.cancel()
            fetchTask = nil
            isLoading = false
            errorMessage = nil
            presentingError = false
            lastRequestedRegion = requestRegion
            return
        }

        if hasFreshData && !eager {
#if DEBUG
            PerformanceMetrics.point(event: .mapFetch, metadata: "Skipped – fresh cache \(fetchMetadata)")
#endif
            fetchTask?.cancel()
            fetchTask = nil
            isLoading = false
            errorMessage = nil
            presentingError = false
            lastRequestedRegion = requestRegion
            return
        }

#if DEBUG
        PerformanceMetrics.point(
            event: .mapFetch,
            metadata: "Scheduled fetch \(fetchMetadata) cacheHit=\(cacheHit != nil)"
        )
#endif
        fetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        presentingError = false
        lastRequestedRegion = requestRegion

        fetchTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performFetchTask(
                requestRegion: requestRegion,
                filter: filter,
                eager: eager,
                cachedOverride: cachedOverride,
                fetchMetadata: fetchMetadata,
                fetchLimit: fetchLimit
            )
        }
        scheduleGlobalDatasetBootstrapIfNeeded()
    }

    @MainActor
    private func performFetchTask(
        requestRegion: MKCoordinateRegion,
        filter: MapFilter,
        eager: Bool,
        cachedOverride: [Place]?,
        fetchMetadata: String,
        fetchLimit: Int
    ) async {
#if DEBUG
        let fetchSpan = PerformanceMetrics.begin(
            event: .mapFetch,
            metadata: fetchMetadata
        )
        var resultMetadata = "cancelled-before-start"
        defer { PerformanceMetrics.end(fetchSpan, metadata: resultMetadata) }
#endif
        if !eager {
            do {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 200_000_000)
                try Task.checkCancellation()
#if DEBUG
                resultMetadata = "debounce-complete"
#endif
            } catch {
#if DEBUG
                resultMetadata = "cancelled-during-debounce"
#endif
                return
            }
        }

        let computationTask = Task.detached(priority: .userInitiated) {
            try await Self.fetchPlacesData(
                requestRegion: requestRegion,
                fetchLimit: fetchLimit
            )
        }

        do {
            try Task.checkCancellation()
            let result = try await computationTask.value
            try Task.checkCancellation()

            let sanitizedCombined = result.sanitizedPlaces
            let sortedPlaces = PlaceOverrides.sorted(sanitizedCombined)

            self.allPlaces = sortedPlaces
            self.mergeIntoGlobalDataset(sanitizedCombined, replacingSources: Set(["seed"]))
            self.apply(filter: self.currentFilter)
            self.isLoading = false
            self.cache.store(sanitizedCombined, region: requestRegion)
            if eager && !result.hitFetchLimit {
                self.scheduleManualOverlay(
                    basePlaces: sortedPlaces,
                    requestRegion: requestRegion,
                    filter: filter
                )
            }
#if DEBUG
            resultMetadata = "success places=\(sanitizedCombined.count) remote=\(result.remoteCount) hitLimit=\(result.hitFetchLimit)"
#endif
        } catch is CancellationError {
            computationTask.cancel()
#if DEBUG
            resultMetadata = "cancelled"
#endif
        } catch {
            computationTask.cancel()
            if let urlError = error as? URLError, urlError.code == .cancelled {
#if DEBUG
                resultMetadata = "url-cancelled"
#endif
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
#if DEBUG
            resultMetadata = "error \(error.localizedDescription)"
#endif
        }
    }

    private struct MapFetchComputationResult: Sendable {
        let sanitizedPlaces: [Place]
        let remoteCount: Int
        let hitFetchLimit: Bool
    }

    private struct SeedBootstrapResult: Sendable {
        let deduplicatedSeeds: [Place]
        let sortedSeeds: [Place]
    }

    private nonisolated static func fetchPlacesData(
        requestRegion: MKCoordinateRegion,
        fetchLimit: Int
    ) async throws -> MapFetchComputationResult {
        try Task.checkCancellation()
        let dtos = try await PlaceAPI.getPlaces(bbox: requestRegion.bbox, limit: fetchLimit)
        try Task.checkCancellation()

        let results = dtos.compactMap(Place.init(dto:)).filteredByCurrentGeoScope()
        let overridden = PlaceOverrides.apply(overridesTo: results, in: requestRegion)
        let cleaned = overridden
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter(Self.trustedSourceFilter)
        let halalOnly = cleaned.filter { $0.halalStatus == .yes || $0.halalStatus == .only }

        try Task.checkCancellation()
        let combined = PlaceOverrides.deduplicate(halalOnly).filteredByCurrentGeoScope()
        let sanitizedCombined = combined.filter(Self.trustedSourceFilter)

        return MapFetchComputationResult(
            sanitizedPlaces: sanitizedCombined,
            remoteCount: halalOnly.count,
            hitFetchLimit: cleaned.count >= fetchLimit
        )
    }

    private func bootstrapFromDiskIfNeeded(region: MKCoordinateRegion, filter: MapFilter) {
        guard !didAttemptDiskBootstrap else { return }
        didAttemptDiskBootstrap = true

        let seedRegion = normalizedRegion(for: region)

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let snapshot = await self.diskCache.loadSnapshot(), !snapshot.places.isEmpty {
                let filtered = snapshot.places
                    .filteredByCurrentGeoScope()
                    .filter(self.isTrustedPlace(_:))
                guard !filtered.isEmpty else {
                    self.ensureGlobalDataset(forceRefresh: true)
                    return
                }
                self.globalDatasetETag = snapshot.globalDatasetETag
                self.restoreCommunitySnapshot(from: snapshot.communityTopRated)
                self.mergeIntoGlobalDataset(filtered, persist: false)
                self.allPlaces = self.globalDataset
                self.apply(filter: filter)
                self.cache.store(self.allPlaces, region: seedRegion)
                self.pendingPersistSnapshotSignature = nil
                self.lastPersistedSnapshotSignature = self.persistenceSnapshotSignature()

                if snapshot.communityTopRated == nil, !self.persistedCommunityTopRated.isEmpty {
                    await self.persistSnapshotImmediately()
                }

                let isStale = Date().timeIntervalSince(snapshot.savedAt) > self.diskSnapshotStalenessInterval
                if isStale {
                    self.ensureGlobalDataset(forceRefresh: true)
                }
            } else {
                let seedTask = Task.detached(priority: .utility) { () -> SeedBootstrapResult in
                    let seeds = Self.loadBundledSeedPlaces()
                    guard !seeds.isEmpty else {
                        return SeedBootstrapResult(deduplicatedSeeds: [], sortedSeeds: [])
                    }
                    let filteredSeeds = seeds.filteredByCurrentGeoScope()
                    let trustedSeeds = filteredSeeds.filter(Self.trustedSourceFilter)
                    guard !trustedSeeds.isEmpty else {
                        return SeedBootstrapResult(deduplicatedSeeds: [], sortedSeeds: [])
                    }
                    let deduplicatedSeeds = PlaceOverrides.deduplicate(trustedSeeds)
                    let sortedSeeds = PlaceOverrides.sorted(deduplicatedSeeds)
                    return SeedBootstrapResult(
                        deduplicatedSeeds: deduplicatedSeeds,
                        sortedSeeds: sortedSeeds
                    )
                }
                let seedResult = await seedTask.value
                if !seedResult.sortedSeeds.isEmpty {
                    if self.globalDataset.isEmpty {
                        self.globalDataset = seedResult.sortedSeeds
                        self.globalDatasetVersion = self.globalDatasetVersion &+ 1
                    }
                    if self.allPlaces.isEmpty {
                        self.allPlaces = seedResult.sortedSeeds
                        self.apply(filter: filter)
                        self.cache.store(seedResult.sortedSeeds, region: seedRegion)
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

    private func dynamicResultLimit(for region: MKCoordinateRegion) -> Int {
        let area = region.span.latitudeDelta * region.span.longitudeDelta
        if area < 0.004 { return PlaceAPI.mapFetchDefaultLimit }
        if area < 0.012 { return 200 }
        if area < 0.028 { return 160 }
        if area < 0.07 { return 130 }
        return 100
    }

    private func scheduleGlobalDatasetBootstrapIfNeeded() {
        guard globalDataset.isEmpty,
              globalDatasetTask == nil,
              globalDatasetBootstrapTask == nil else { return }
        globalDatasetBootstrapTask = Task { [weak self] in
            defer {
                if let strongSelf = self {
                    strongSelf.globalDatasetBootstrapTask = nil
                }
            }
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let strongSelf = self else { return }
            strongSelf.ensureGlobalDataset()
        }
    }

    private func globalDatasetSlice(for region: MKCoordinateRegion, limit: Int) -> [Place]? {
        guard !globalDataset.isEmpty else { return nil }
        let bbox = region.bbox

        let bounded = globalDataset.filter { place in
            let coordinate = place.coordinate
            let latitude = coordinate.latitude
            let longitude = coordinate.longitude
            return latitude >= bbox.south &&
                latitude <= bbox.north &&
                longitude >= bbox.west &&
                longitude <= bbox.east
        }
        guard !bounded.isEmpty else { return nil }

        let scoped = bounded
            .filteredByCurrentGeoScope()
            .filter(isTrustedPlace)
        guard !scoped.isEmpty else { return nil }

        if scoped.count > limit {
            return Array(scoped.prefix(limit))
        }
        return scoped
    }

    private func scheduleManualOverlay(
        basePlaces: [Place],
        requestRegion: MKCoordinateRegion,
        filter: MapFilter
    ) {
        manualOverlayTask?.cancel()
        manualOverlayTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            defer { self.manualOverlayTask = nil }

            guard let latestRegion = self.lastRequestedRegion,
                  self.regionIsSimilar(lhs: latestRegion, rhs: requestRegion) else { return }

            let exclusion = basePlaces + self.allPlaces + self.globalDataset
            let manual = await ManualPlaceResolver
                .shared
                .manualPlaces(in: Self.appleFallbackRegion, excluding: exclusion)
                .filteredByCurrentGeoScope()
                .filter(Self.trustedSourceFilter)

            guard !Task.isCancelled else { return }
            guard !manual.isEmpty else { return }

            let combined = self.deduplicate(basePlaces + manual).filteredByCurrentGeoScope()
            let sanitizedCombined = combined.filter(self.isTrustedPlace(_:))
            guard !sanitizedCombined.isEmpty else { return }

            let sorted = PlaceOverrides.sorted(sanitizedCombined)
            guard sorted != self.allPlaces else { return }

            self.allPlaces = sorted
            self.mergeIntoGlobalDataset(manual)
            self.apply(filter: filter)
            self.cache.store(sanitizedCombined, region: requestRegion)
        }
    }

    private func schedulePersistGlobalDataset() {
        guard !globalDataset.isEmpty else { return }
        let snapshotSignature = persistenceSnapshotSignature()
        if snapshotSignature == lastPersistedSnapshotSignature || snapshotSignature == pendingPersistSnapshotSignature {
            return
        }

        pendingPersistSnapshotSignature = snapshotSignature
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingPersistSnapshotSignature == snapshotSignature {
                    self.pendingPersistSnapshotSignature = nil
                }
            }
            do {
                try await Task.sleep(nanoseconds: persistDebounceNanoseconds)
            } catch {
                return
            }
            let snapshot = self.globalDataset
            guard !snapshot.isEmpty else { return }
            let communityPayload = self.serializedCommunityTopRated()
            let etag = self.globalDatasetETag
            await self.diskCache.saveSnapshot(
                places: snapshot,
                communityTopRated: communityPayload,
                eTag: etag
            )
            self.lastPersistedSnapshotSignature = snapshotSignature
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
            hasher.combine(place.address ?? "")
            hasher.combine(place.source ?? "")
        }
        return hasher.finalize()
    }

    private func persistenceSnapshotSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(persistenceFingerprint(for: globalDataset))
        hasher.combine(globalDatasetETag ?? "")
        let sortedRegions = persistedCommunityTopRated.keys.sorted { $0.rawValue < $1.rawValue }
        for region in sortedRegions {
            hasher.combine(region.rawValue)
            let list = persistedCommunityTopRated[region] ?? []
            hasher.combine(list.count)
            for place in list.prefix(20) {
                hasher.combine(place.id)
                hasher.combine(place.rating ?? -1)
                hasher.combine(place.ratingCount ?? -1)
            }
        }
        return hasher.finalize()
    }

    private func serializedCommunityTopRated() -> [String: [Place]]? {
        guard !persistedCommunityTopRated.isEmpty else { return nil }
        var payload: [String: [Place]] = [:]
        for (region, list) in persistedCommunityTopRated {
            guard !list.isEmpty else { continue }
            payload[region.rawValue] = Array(list.prefix(20))
        }
        return payload.isEmpty ? nil : payload
    }

    private func restoreCommunitySnapshot(from raw: [String: [Place]]?) {
        guard let raw else {
            persistedCommunityTopRated = [:]
            return
        }
        var restored: [TopRatedRegion: [Place]] = [:]
        for (key, list) in raw {
            guard let region = TopRatedRegion(rawValue: key) else { continue }
            let cleaned = list
                .filteredByCurrentGeoScope()
                .filter(isTrustedPlace)
            guard !cleaned.isEmpty else { continue }
            let deduped = PlaceOverrides.deduplicate(cleaned)
            let sorted = PlaceOverrides.sorted(deduped)
            guard !sorted.isEmpty else { continue }
            restored[region] = Array(sorted.prefix(20))
        }
        persistedCommunityTopRated = restored
    }

    private func normalizedCommunityResults(_ results: [TopRatedRegion: [Place]]) -> [TopRatedRegion: [Place]] {
        var normalized: [TopRatedRegion: [Place]] = [:]
        for (region, list) in results {
            guard !list.isEmpty else { continue }
            let cleaned = list
                .filteredByCurrentGeoScope()
                .filter(isTrustedPlace)
            guard !cleaned.isEmpty else { continue }
            let deduped = PlaceOverrides.deduplicate(cleaned)
            let sorted = PlaceOverrides.sorted(deduped)
            guard !sorted.isEmpty else { continue }
            normalized[region] = Array(sorted.prefix(20))
        }
        return normalized
    }

    private func persistSnapshotImmediately() async {
        guard !globalDataset.isEmpty else { return }
        let payload = serializedCommunityTopRated()
        let etag = globalDatasetETag
        await diskCache.saveSnapshot(
            places: globalDataset,
            communityTopRated: payload,
            eTag: etag
        )
        lastPersistedSnapshotSignature = persistenceSnapshotSignature()
        pendingPersistSnapshotSignature = nil
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
        case .zabihahHalal:
            filtered = allPlaces.filter { $0.certifierOrg != nil }
        }
        places = filtered
    }

    fileprivate func communityTopRatedSnapshot() -> CommunityTopRatedSnapshot {
        return CommunityTopRatedSnapshot(
            allPlaces: allPlaces,
            globalPlaces: globalDataset,
            searchResults: searchResults,
            googleFallback: googleCandidatePlaces(limit: 80),
            hasTrustedData: hasTrustedCommunityDataset()
        )
    }

    fileprivate nonisolated static func fetchCommunityTopRated(limitPerRegion: Int = 20) async throws -> [TopRatedRegion: [Place]] {
        let rows = try await PlaceAPI.fetchCommunityTopRated(limitPerRegion: limitPerRegion)
        try Task.checkCancellation()

        var buckets: [TopRatedRegion: [(rank: Int, place: Place)]] = [:]
        buckets.reserveCapacity(rows.count)

        for record in rows {
            guard let region = TopRatedRegion(rawValue: record.region) else { continue }
            let dto = record.toPlaceDTO()
            guard let place = Place(dto: dto) else { continue }
            guard trustedSourceFilter(place) else { continue }
            if let rawURL = record.primaryImageURL, let original = URL(string: rawURL) {
                let optimized = TopRatedPhotoThumb.optimizedURL(from: original)
                await TopRatedPhotoThumb.cache(optimized, for: place.id)
            }
            buckets[region, default: []].append((rank: record.regionRank, place: place))
        }

        var result: [TopRatedRegion: [Place]] = [:]
        for (region, entries) in buckets {
            let ordered = entries.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.place.name < rhs.place.name
            }.map { $0.place }
            let filtered = ordered
                .filteredByCurrentGeoScope()
                .filter(trustedSourceFilter)
            var deduplicated: [Place] = []
            deduplicated.reserveCapacity(filtered.count)
            var seen = Set<UUID>()
            for place in filtered where seen.insert(place.id).inserted {
                deduplicated.append(place)
            }
            guard !deduplicated.isEmpty else { continue }
            let regionLimit = region == .all ? max(limitPerRegion * 3, limitPerRegion) : limitPerRegion
            result[region] = Array(deduplicated.prefix(regionLimit))
        }

        if result[.all] == nil {
            let combined = CommunityTopRatedConfig.regions
                .flatMap { result[$0] ?? [] }
            if !combined.isEmpty {
                var seen = Set<UUID>()
                var deduplicated: [Place] = []
                deduplicated.reserveCapacity(combined.count)
                for place in combined {
                    let normalized = PlaceOverrides.normalizedName(for: place.name)
                    if CommunityTopRatedConfig.excludedFromAllLocations.contains(normalized) {
                        continue
                    }
                    if seen.insert(place.id).inserted {
                        deduplicated.append(place)
                    }
                }
                if !deduplicated.isEmpty {
                    let fallbackLimit = max(limitPerRegion * 3, limitPerRegion)
                    result[.all] = Array(deduplicated.prefix(fallbackLimit))
                }
            }
        }

        return result
    }

    fileprivate func persistCommunityTopRated(_ results: [TopRatedRegion: [Place]]) {
        let normalized = normalizedCommunityResults(results)
        guard normalized != persistedCommunityTopRated else { return }
        persistedCommunityTopRated = normalized
        schedulePersistGlobalDataset()
    }

    func hasTrustedCommunityDataset() -> Bool {
        let combined = allPlaces + globalDataset
        guard !combined.isEmpty else { return false }
        return combined.contains { !isSeedPlace($0) }
    }

    func topRatedPlaces(limit: Int = 50, minimumReviews: Int = 10) -> [Place] {
        let source: [Place]
        if !globalDataset.isEmpty {
            source = globalDataset
        } else {
            source = allPlaces
        }

        let candidates = source.filter { place in
            guard let rating = place.displayRating, rating > 0 else { return false }
            return (place.displayRatingCount ?? 0) >= minimumReviews
        }

        let sorted = candidates.sorted { lhs, rhs in
            switch (lhs.displayRating, rhs.displayRating) {
            case let (l?, r?) where l != r:
                return l > r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let lhsCount = lhs.displayRatingCount ?? 0
                let rhsCount = rhs.displayRatingCount ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        if sorted.count <= limit { return sorted }
        return Array(sorted.prefix(limit))
    }

    fileprivate func googleCandidatePlaces(limit: Int = 60, region: TopRatedRegion = .all) -> [Place] {
        ensureGoogleCandidateCacheIfNeeded()
        let base = googleCandidatesAllCache
        let filtered: [Place]
        if region == .all {
            filtered = base
        } else {
            filtered = base.filter { CommunityRegionClassifier.matches($0, region: region) }
        }
        if filtered.count <= limit { return filtered }
        return Array(filtered.prefix(limit))
    }

    private func ensureGoogleCandidateCacheIfNeeded() {
        let signature = currentGoogleCandidateCacheSignature()
        guard googleCandidateCacheSignature != signature else { return }
        googleCandidateCacheSignature = signature

        let source = globalDataset.isEmpty ? allPlaces : globalDataset
        let googleBacked = source.filter { place in
            place.hasGooglePlaceID && place.isGoogleMatched && !place.isGoogleClosed
        }
        googleCandidatesAllCache = PlaceOverrides.deduplicate(googleBacked)
    }

    private func currentGoogleCandidateCacheSignature() -> Int {
        var value = globalDatasetVersion &+ filteredPlacesVersion
        value = value &+ (globalDataset.count &* 31)
        value = value &+ (allPlaces.count &* 17)
        return value
    }

    func curatedPlaces(matching tokens: Set<String>) -> [Place] {
        guard !tokens.isEmpty else { return [] }

        let pools: [[Place]] = [globalDataset, allPlaces, searchResults]
        var seen = Set<UUID>()
        var matches: [Place] = []
        matches.reserveCapacity(16)

        for pool in pools {
            for place in pool where seen.insert(place.id).inserted {
                guard isTrustedPlace(place) else { continue }
                let normalized = PlaceOverrides.normalizedName(for: place.name)
                if tokens.contains(where: { normalized.contains($0) }) {
                    matches.append(place)
                }
            }
        }

        guard !matches.isEmpty else { return [] }

        let scoped = matches.filteredByCurrentGeoScope()
        guard !scoped.isEmpty else { return [] }

        return PlaceOverrides.sorted(scoped)
    }

    private func isSeedPlace(_ place: Place) -> Bool {
        guard let source = place.source?.lowercased() else { return false }
        return source == "seed"
    }

    private func regionIsSimilar(lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        lhs.isApproximatelyEqual(to: rhs)
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? PlaceAPIError {
            switch apiError {
            case .missingConfiguration:
                return "Supabase credentials missing. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist or your environment."
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
    nonisolated struct PlaceSeed: Decodable {
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

    nonisolated static let nonHalalChainBlocklist: Set<String> = {
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
        globalDatasetBootstrapTask?.cancel()
        globalDatasetBootstrapTask = nil
        if !forceRefresh {
            guard globalDataset.isEmpty, globalDatasetTask == nil else {
#if DEBUG
                PerformanceMetrics.point(
                    event: .globalDatasetFetch,
                    metadata: "Skipped ensureGlobalDataset – cached=\(!globalDataset.isEmpty) taskRunning=\(globalDatasetTask != nil)"
                )
#endif
                return
            }
        } else {
#if DEBUG
            PerformanceMetrics.point(event: .globalDatasetFetch, metadata: "Force refresh requested")
#endif
            guard globalDatasetTask == nil else {
#if DEBUG
                PerformanceMetrics.point(event: .globalDatasetFetch, metadata: "Skipped force refresh – task already running")
#endif
                return
            }
        }

        let cachedETag = globalDatasetETag

        let task = Task(priority: .utility) { [weak self] in
#if DEBUG
            let span = PerformanceMetrics.begin(
                event: .globalDatasetFetch,
                metadata: "fetchAllPlaces force=\(forceRefresh)"
            )
            var resultMetadata = "cancelled-before-start"
#endif
            do {
                let response = try await PlaceAPI.fetchAllPlaces(
                    limit: 3500,
                    pageSize: 800,
                    ifNoneMatch: cachedETag
                )

                if response.notModified {
#if DEBUG
                    resultMetadata = "not-modified"
                    PerformanceMetrics.point(
                        event: .globalDatasetFetch,
                        metadata: "Supabase returned 304 for global dataset"
                    )
                    PerformanceMetrics.end(span, metadata: resultMetadata)
#endif
                    await MainActor.run {
                        guard let self else { return }
                        self.globalDatasetETag = response.eTag ?? cachedETag
                        self.globalDatasetTask = nil
                        self.updateSearchActivityIndicator()
                    }
                    return
                }

                let places = response.places
                    .compactMap(Place.init(dto:))
                    .filteredByCurrentGeoScope()
                    .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .filter(MapScreenViewModel.trustedSourceFilter)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    self.globalDatasetETag = response.eTag
                    self.mergeIntoGlobalDataset(places, replacingSources: Set(["seed"]))
                    if let query = self.lastSearchQuery, !query.isEmpty {
                        let seeded = self.combinedMatches(for: query).filteredByCurrentGeoScope()
                        self.searchResults = PlaceOverrides.sorted(seeded)
                    }
                    self.globalDatasetTask = nil
                    self.updateSearchActivityIndicator()
                }
#if DEBUG
                resultMetadata = "success places=\(places.count)"
#endif
            } catch is CancellationError {
#if DEBUG
                resultMetadata = "cancelled"
                PerformanceMetrics.point(event: .globalDatasetFetch, metadata: "Global dataset fetch cancelled")
#endif
                await MainActor.run {
                    if let self {
                        self.globalDatasetTask = nil
                        self.updateSearchActivityIndicator()
                    }
                }
            } catch {
#if DEBUG
                resultMetadata = "error \(error.localizedDescription)"
                PerformanceMetrics.point(
                    event: .globalDatasetFetch,
                    metadata: "Failed to load global dataset – \(error.localizedDescription)"
                )
#endif
                await MainActor.run {
                    if let self {
                        self.globalDatasetTask = nil
                        self.updateSearchActivityIndicator()
                    }
                }
            }
#if DEBUG
            PerformanceMetrics.end(span, metadata: resultMetadata)
#endif
        }

        globalDatasetTask = task
        updateSearchActivityIndicator()
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
        if !filtered.isEmpty {
            let incomingIDs = Set(filtered.map(\.id))
            if !incomingIDs.isEmpty {
                sanitizedExisting.removeAll { incomingIDs.contains($0.id) }
            }
        }
        guard !(filtered.isEmpty && sanitizedExisting == globalDataset) else { return }

        let combined = deduplicate(sanitizedExisting + filtered)
        let sorted = PlaceOverrides.sorted(combined)
        if sorted != globalDataset {
            globalDataset = sorted
            globalDatasetVersion = globalDatasetVersion &+ 1
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

    nonisolated static func loadBundledSeedPlaces() -> [Place] {
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

    func datasetForRefinedFilters() -> [Place] {
        let union = deduplicate(allPlaces + globalDataset)
        let trusted = union.filter(isTrustedPlace)
        return PlaceOverrides.sorted(trusted)
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
                   halalStatus: Place.HalalStatus) -> Place? {
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
            source: "apple",
            applePlaceID: mapItem.halalPersistentIdentifier
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

        let refreshedEntry = Entry(places: entry.places, timestamp: Date())
        storage[key] = refreshedEntry
        return (refreshedEntry.places, age < ttl)
    }
}

private extension MapScreenViewModel {
    nonisolated static func trustedSourceFilter(_ place: Place) -> Bool {
        if isBlocklistedChain(place) { return false }
        if place.isGoogleClosed { return false }
        if !place.isGoogleMatched { return false }
        guard let rawSource = place.source?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSource.isEmpty else {
            return true
        }
        let normalized = rawSource.lowercased()
        if normalized.contains("apple") {
            return normalized.hasPrefix("apple")
        }
        return true
    }

    func isTrustedPlace(_ place: Place) -> Bool {
        Self.trustedSourceFilter(place)
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

private extension ContentView {
    func centerMap(on location: CLLocation, span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08), markCentered: Bool = true) {
        let region = MKCoordinateRegion(center: location.coordinate, span: span)
        mapRegion = region
        if shouldFetchDetails(for: region) {
            viewModel.forceRefresh(region: region, filter: selectedFilter)
        }
        let effective = RegionGate.enforcedRegion(for: region)
        appleHalalSearch.search(in: effective)
        if markCentered {
            hasCenteredOnUser = true
        }
        refreshVisiblePlaces()
        refreshVisiblePins()
    }
}

private struct MapTabContainer: View {
    @Binding var mapRegion: MKCoordinateRegion
    @Binding var selectedPlace: Place?
    @Binding var selectedApplePlace: ApplePlaceSelection?
    let pins: [PlacePin]
    let places: [Place]
    let appleMapItems: [MKMapItem]
    let isLoading: Bool
    let shouldShowLoadingIndicator: Bool
    let onRegionChange: (MKCoordinateRegion) -> Void
    let onPinSelected: (PlacePin) -> Void
    let onPlaceSelected: (Place) -> Void
    let onAppleItemSelected: (MKMapItem) -> Void
    let onMapTap: () -> Void

    var body: some View {
        ZStack {
            HalalMapView(
                region: $mapRegion,
                selectedPlace: $selectedPlace,
                pins: pins,
                places: places,
                appleMapItems: appleMapItems,
                onRegionChange: onRegionChange,
                onPinSelected: onPinSelected,
                onPlaceSelected: onPlaceSelected,
                onAppleItemSelected: onAppleItemSelected,
                onMapTap: onMapTap
            )
            .ignoresSafeArea()

            if shouldShowLoadingIndicator {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(16)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

#Preview {
    ContentView()
}
