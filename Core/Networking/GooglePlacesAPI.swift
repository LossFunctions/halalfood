import Foundation

enum GooglePlacesAPI {
    static func fetchPlace(googlePlaceID: String) async throws -> GooglePlaceData {
        guard let baseURL = Env.optionalURL(),
              let anonKey = Env.optionalAnonKey() else {
            throw GooglePlacesAPIError.missingConfiguration
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        if !path.hasSuffix("/") { path.append("/") }
        path.append("functions/v1/google_places_proxy")
        components?.path = path

        guard let url = components?.url else {
            throw GooglePlacesAPIError.invalidURL
        }

        let payload = ["place_id": googlePlaceID]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GooglePlacesAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            throw GooglePlacesAPIError.server(statusCode: httpResponse.statusCode, body: bodyString)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let payloadResponse = try decoder.decode(GoogleProxyResponse.self, from: data)
        let photos = payloadResponse.photos.enumerated().map { index, photo in
            GooglePhotoData(
                position: photo.position ?? index,
                url: photo.url,
                attribution: photo.attribution,
                reference: photo.reference,
                width: photo.width,
                height: photo.height
            )
        }.sorted { $0.position < $1.position }

        let fetchedAt = payloadResponse.fetchedAt ?? Date()
        let maxExpiresAt = fetchedAt.addingTimeInterval(GooglePlaceData.maxCacheAge)
        let expiresAt = min(payloadResponse.expiresAt ?? maxExpiresAt, maxExpiresAt)

        return GooglePlaceData(
            placeID: payloadResponse.placeId,
            rating: payloadResponse.rating,
            reviewCount: payloadResponse.reviewCount,
            mapsURL: payloadResponse.mapsUrl,
            businessStatus: payloadResponse.businessStatus,
            phoneNumber: payloadResponse.phoneNumber,
            websiteURL: payloadResponse.websiteUrl,
            formattedAddress: payloadResponse.formattedAddress,
            openingHours: payloadResponse.openingHours,
            photos: photos,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt
        )
    }
}

enum GooglePlacesAPIError: Error {
    case missingConfiguration
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, body: String?)
}

nonisolated struct GooglePlaceData: Codable, Equatable {
    static let maxCacheAge: TimeInterval = 60 * 60 * 23 + 60 * 55
    static let refreshWindow: TimeInterval = 60 * 60

    let placeID: String
    let rating: Double?
    let reviewCount: Int?
    let mapsURL: String?
    let businessStatus: String?
    let phoneNumber: String?
    let websiteURL: String?
    let formattedAddress: String?
    let openingHours: GoogleOpeningHours?
    let photos: [GooglePhotoData]
    let fetchedAt: Date
    let expiresAt: Date
}

nonisolated extension GooglePlaceData {
    var effectiveExpiresAt: Date {
        let maxExpiresAt = fetchedAt.addingTimeInterval(Self.maxCacheAge)
        return min(expiresAt, maxExpiresAt)
    }

    var isExpired: Bool {
        effectiveExpiresAt <= Date()
    }

    var isNearExpiry: Bool {
        let remaining = effectiveExpiresAt.timeIntervalSinceNow
        return remaining > 0 && remaining <= Self.refreshWindow
    }
}

nonisolated struct GooglePhotoData: Codable, Equatable {
    let position: Int
    let url: String
    let attribution: String?
    let reference: String?
    let width: Int?
    let height: Int?
}

nonisolated struct GoogleOpeningHours: Codable, Equatable {
    let weekdayDescriptions: [String]?
    let openNow: Bool?
}

nonisolated private struct GoogleProxyResponse: Decodable {
    let placeId: String
    let rating: Double?
    let reviewCount: Int?
    let mapsUrl: String?
    let businessStatus: String?
    let phoneNumber: String?
    let websiteUrl: String?
    let formattedAddress: String?
    let openingHours: GoogleOpeningHours?
    let photos: [GoogleProxyPhoto]
    let fetchedAt: Date?
    let expiresAt: Date?
}

nonisolated private struct GoogleProxyPhoto: Decodable {
    let position: Int?
    let url: String
    let attribution: String?
    let reference: String?
    let width: Int?
    let height: Int?
}
