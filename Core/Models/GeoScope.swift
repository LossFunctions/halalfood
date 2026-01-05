import Foundation
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif

// Simple axis-aligned bounding box utility (distinct from Networking.BBox)
struct GeoBBox {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    func contains(lat: Double, lon: Double) -> Bool {
        (lat >= minLat && lat <= maxLat) && (lon >= minLon && lon <= maxLon)
    }
}

/// Region gate that limits rendering to NYC and Long Island while preserving
/// existing data sources (Yelp/CSV/Apple Maps). Toggle via Info.plist key
/// `LIMIT_TO_NYC_LONG_ISLAND` (true = limit, false = allow all).
///
/// Usage:
///   if RegionGate.allows(lat: item.lat, lon: item.lon, state: item.state, country: item.country) {
///       // render
///   }
///
/// If `state` is provided and not `NY`, items are rejected even if within LI bbox.
struct RegionGate {
    // NYC five boroughs bbox
    private static let nyc = GeoBBox(
        minLat: 40.4774, minLon: -74.2591,
        maxLat: 40.9176, maxLon: -73.7004
    )

    // Long Island (Nassau + Suffolk) coarse bbox
    private static let longIsland = GeoBBox(
        minLat: 40.50, minLon: -73.75,
        maxLat: 41.15, maxLon: -71.85
    )

    // Reads Info.plist key; defaults to true when missing.
    private static var defaultLimitEnabled: Bool = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "LIMIT_TO_NYC_LONG_ISLAND") as? Bool {
            return value
        }
        return true
    }()

    private static var overrideLimit: Bool?

    private static var limitEnabled: Bool { overrideLimit ?? defaultLimitEnabled }

    static func allows(lat: Double, lon: Double, state: String? = nil, country: String? = nil) -> Bool {
        guard limitEnabled else { return true }

        // Always require US if provided
        if let country = country, !countryIsUS(country) { return false }
        if let state = state, !stateIsNY(state) { return false }

        if nyc.contains(lat: lat, lon: lon) { return true }

        // For Long Island, prefer NY state if provided to avoid CT shoreline spillover
        if longIsland.contains(lat: lat, lon: lon) {
            if let state = state {
                return stateIsNY(state)
            }
            // No state info; accept based on coordinate alone
            return true
        }

        return false
    }

    /// Optionally override the Info.plist driven behavior at runtime.
    /// Pass nil to clear the override and revert to Info.plist value.
    static func setLimitEnabled(_ enabled: Bool?) {
        overrideLimit = enabled
    }

#if canImport(MapKit)
    /// Convenience: A visible region that covers NYC + Long Island.
    static var nycLongIslandCoordinateRegion: MKCoordinateRegion {
        // Union of NYC and LI bboxes
        let minLat = min(nyc.minLat, longIsland.minLat)
        let minLon = min(nyc.minLon, longIsland.minLon)
        let maxLat = max(nyc.maxLat, longIsland.maxLat)
        let maxLon = max(nyc.maxLon, longIsland.maxLon)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.1,
            longitudeDelta: (maxLon - minLon) * 1.1
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Returns the enforced region to query against when limiting is enabled.
    /// If limiting is disabled, returns the input region unchanged.
    static func enforcedRegion(for region: MKCoordinateRegion) -> MKCoordinateRegion {
        guard limitEnabled else { return region }
        return nycLongIslandCoordinateRegion
    }

    /// Filter MKMapItem (Apple Maps search results)
    static func allows(mapItem: MKMapItem) -> Bool {
        let coord = mapItem.placemark.coordinate
        let state = mapItem.placemark.administrativeArea
        let country = mapItem.placemark.isoCountryCode
        return allows(lat: coord.latitude, lon: coord.longitude, state: state, country: country)
    }
#endif

    private static func stateIsNY(_ s: String) -> Bool {
        let x = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return x == "NY" || x == "NEW YORK"
    }

    private static func countryIsUS(_ s: String) -> Bool {
        let x = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return x == "US" || x == "USA" || x == "UNITED STATES"
    }

    // Heuristic: pull a US state code from common address formats.
    // Looks for patterns like ", NY" or " NY " or " NY," optionally before ZIP.
    static func deriveUSStateCode(fromAddress address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()

        // Quick city, ST form
        // Examples: "Brooklyn, NY 11211", "Jersey City, NJ", "Stamford, CT"
        let tokens = upper.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for token in tokens {
            if token.count >= 2 {
                // Match two-letter state code, either by itself or followed by ZIP
                // e.g., "NY 11211" or just "NY"
                let parts = token.split(separator: " ")
                if let first = parts.first, first.count == 2 {
                    let code = String(first)
                    if Self.isTwoLetterUSState(code) { return code }
                }
            }
        }

        let fullStateNames: [(String, String)] = [
            ("NEW JERSEY", "NJ"),
            ("NEW YORK", "NY"),
            ("CONNECTICUT", "CT")
        ]
        for (name, code) in fullStateNames where upper.contains(name) {
            return code
        }

        // Fallback: scan entire string for isolated two-letter state
        let words = upper.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for w in words where w.count == 2 {
            let code = String(w)
            if Self.isTwoLetterUSState(code) { return code }
        }

        return nil
    }

    private static func isTwoLetterUSState(_ code: String) -> Bool {
        let states: Set<String> = [
            "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC"
        ]
        return states.contains(code)
    }
}

/// Optional protocol to adopt on your place model so you can filter collections
/// succinctly without rewriting closures at each call site.
protocol Geolocated {
    var latitude: Double { get }
    var longitude: Double { get }
    var state: String? { get }
    var country: String? { get }
}

extension Sequence where Element: Geolocated {
    func filteredByCurrentGeoScope() -> [Element] {
        self.filter { RegionGate.allows(lat: $0.latitude, lon: $0.longitude, state: $0.state, country: $0.country) }
    }
}

// Specialization for Place: also derive state from address and enforce NY to avoid NJ/CT spillover.
extension Sequence where Element == Place {
    func filteredByCurrentGeoScope() -> [Place] {
        self.filter { place in
            guard RegionGate.allows(lat: place.coordinate.latitude, lon: place.coordinate.longitude) else { return false }
            if let address = place.address, let state = RegionGate.deriveUSStateCode(fromAddress: address) {
                return state == "NY"
            }
            return true
        }
    }
}

extension Sequence where Element == PlacePin {
    func filteredByCurrentGeoScope() -> [PlacePin] {
        self.filter { pin in
            guard RegionGate.allows(lat: pin.latitude, lon: pin.longitude) else { return false }
            if let address = pin.address, let state = RegionGate.deriveUSStateCode(fromAddress: address) {
                return state == "NY"
            }
            return true
        }
    }
}
