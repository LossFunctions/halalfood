import Foundation
import MapKit
import CoreLocation

struct ApplePlaceDetails {
    let mapItem: MKMapItem

    var applePlaceID: String? {
        mapItem.halalPersistentIdentifier
    }

    var displayName: String {
        mapItem.name ?? ""
    }

    var fullAddress: String? {
        mapItem.halalFullAddress
    }

    var shortAddress: String? {
        mapItem.halalShortAddress
    }

    var phoneNumber: String? {
        mapItem.phoneNumber
    }

    var websiteURL: URL? {
        mapItem.url
    }

    var coordinate: CLLocationCoordinate2D {
        mapItem.halalCoordinate
    }

    var pointOfInterestCategory: MKPointOfInterestCategory? {
        mapItem.pointOfInterestCategory
    }
}

enum ApplePlaceDetailServiceError: LocalizedError {
    case noMatchingPlace
    case mapKitDenied
    case lookupFailed

    var errorDescription: String? {
        switch self {
        case .noMatchingPlace:
            return "We couldn't find a matching Apple Maps place."
        case .mapKitDenied:
            return "Apple Maps couldn't authorize this lookup right now."
        case .lookupFailed:
            return "Apple Maps place details are unavailable."
        }
    }
}

@MainActor
final class ApplePlaceDetailService {
    static let shared = ApplePlaceDetailService()

    private let maxMatchDistance: CLLocationDistance = 1500
    private var cache: [UUID: ApplePlaceDetails] = [:]
    private var identifierCache: [String: ApplePlaceDetails] = [:]
    private var inFlightTasks: [UUID: Task<ApplePlaceDetails, Error>] = [:]

    func details(for place: Place) async throws -> ApplePlaceDetails {
        if let cached = cache[place.id] {
            return cached
        }

        if let storedID = place.applePlaceID, let cached = identifierCache[storedID] {
            cache[place.id] = cached
            return cached
        }

        if let active = inFlightTasks[place.id] {
            return try await active.value
        }

        let task = Task<ApplePlaceDetails, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchDetails(for: place)
        }
        inFlightTasks[place.id] = task
        defer { inFlightTasks[place.id] = nil }

        let resolved = try await task.value
        cache[place.id] = resolved
        if let appleID = resolved.applePlaceID {
            identifierCache[appleID] = resolved
            let placeID = place.id
            Task.detached {
                do {
                    _ = try await PlaceAPI.saveApplePlaceID(for: placeID, applePlaceID: appleID)
                } catch {
#if DEBUG
                    print("[ApplePlaceDetailService] Failed to persist Apple Place ID:", error)
#endif
                }
            }
        }
        return resolved
    }

    private func fetchDetails(for place: Place) async throws -> ApplePlaceDetails {
        if #available(iOS 18.0, *),
           let appleID = place.applePlaceID,
           let identifier = MKMapItem.Identifier(rawValue: appleID) {
            do {
                let request = MKMapItemRequest(mapItemIdentifier: identifier)
                let mapItem = try await request.mapItem
                return ApplePlaceDetails(mapItem: mapItem)
            } catch {
#if DEBUG
                print("[ApplePlaceDetailService] MapItem lookup failed for persisted identifier, will fall back to search:", error)
#endif
            }
        }

        let mapItem = try await locateViaSearch(for: place)
        return ApplePlaceDetails(mapItem: mapItem)
    }

    private func locateViaSearch(for place: Place) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.name
        request.region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: maxMatchDistance * 2, longitudinalMeters: maxMatchDistance * 2)
        request.resultTypes = [.pointOfInterest, .address]

        let search = MKLocalSearch(request: request)

        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch let error as MKError {
            switch error.code {
            case .placemarkNotFound:
                throw ApplePlaceDetailServiceError.noMatchingPlace
            case .loadingThrottled, .serverFailure:
                throw ApplePlaceDetailServiceError.lookupFailed
            default:
                throw error
            }
        } catch {
            throw ApplePlaceDetailServiceError.lookupFailed
        }

        guard let match = bestMatch(in: response.mapItems, for: place) else {
            throw ApplePlaceDetailServiceError.noMatchingPlace
        }
        return match
    }

    private func bestMatch(in candidates: [MKMapItem], for place: Place) -> MKMapItem? {
        guard !candidates.isEmpty else { return nil }
        let normalizedTargetName = normalize(place.name)
        let targetLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)

        struct CandidateScore {
            let item: MKMapItem
            let distance: CLLocationDistance
            let nameScore: Double

            var overall: Double { distance + nameScore }
        }

        let scored = candidates.compactMap { item -> CandidateScore? in
            let coordinate = item.halalCoordinate
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = targetLocation.distance(from: location)
            guard distance <= maxMatchDistance else { return nil }

            let normalizedName = normalize(item.name ?? "")
            let nameScore: Double
            if normalizedName.isEmpty || normalizedTargetName.isEmpty {
                nameScore = 200
            } else if normalizedName == normalizedTargetName {
                nameScore = 0
            } else if normalizedName.contains(normalizedTargetName) || normalizedTargetName.contains(normalizedName) {
                nameScore = 50
            } else {
                nameScore = 150
            }

            return CandidateScore(item: item, distance: distance, nameScore: nameScore)
        }

        return scored.min(by: { $0.overall < $1.overall })?.item
    }

    private func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics
        return folded.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
    }
}
