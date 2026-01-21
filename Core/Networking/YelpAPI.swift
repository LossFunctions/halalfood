import Foundation

enum YelpAPI {
    static func fetchBusiness(yelpID: String) async throws -> YelpBusinessData {
        guard let baseURL = Env.optionalURL(),
              let anonKey = Env.optionalAnonKey() else {
            throw YelpAPIError.missingConfiguration
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        if !path.hasSuffix("/") { path.append("/") }
        path.append("functions/v1/yelp_proxy")
        components?.path = path

        guard let url = components?.url else {
            throw YelpAPIError.invalidURL
        }

        let payload = ["yelp_id": yelpID]
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
            throw YelpAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            throw YelpAPIError.server(statusCode: httpResponse.statusCode, body: bodyString)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let payloadResponse = try decoder.decode(YelpProxyResponse.self, from: data)
        let photos = payloadResponse.photos.enumerated().map { index, photo in
            YelpPhotoData(
                position: photo.position ?? index,
                url: photo.url,
                attribution: photo.attribution
            )
        }.sorted { $0.position < $1.position }

        let fetchedAt = payloadResponse.fetchedAt ?? Date()
        let maxExpiresAt = fetchedAt.addingTimeInterval(YelpBusinessData.maxCacheAge)
        let expiresAt = min(payloadResponse.expiresAt ?? maxExpiresAt, maxExpiresAt)

        return YelpBusinessData(
            yelpID: payloadResponse.yelpId,
            rating: payloadResponse.rating,
            reviewCount: payloadResponse.reviewCount,
            yelpURL: payloadResponse.yelpUrl,
            photos: photos,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt
        )
    }
}

enum YelpAPIError: Error {
    case missingConfiguration
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, body: String?)
}

struct YelpBusinessData: Codable, Equatable {
    static let maxCacheAge: TimeInterval = 60 * 60 * 23 + 60 * 55
    static let refreshWindow: TimeInterval = 60 * 60

    let yelpID: String
    let rating: Double?
    let reviewCount: Int?
    let yelpURL: String?
    let photos: [YelpPhotoData]
    let fetchedAt: Date
    let expiresAt: Date
}

extension YelpBusinessData {
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

struct YelpPhotoData: Codable, Equatable {
    let position: Int
    let url: String
    let attribution: String?
}

private struct YelpProxyResponse: Decodable {
    let yelpId: String
    let rating: Double?
    let reviewCount: Int?
    let yelpUrl: String?
    let photos: [YelpProxyPhoto]
    let fetchedAt: Date?
    let expiresAt: Date?
}

private struct YelpProxyPhoto: Decodable {
    let position: Int?
    let url: String
    let attribution: String?
}
