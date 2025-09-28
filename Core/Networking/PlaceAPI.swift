import Foundation

struct BBox {
    let west: Double
    let south: Double
    let east: Double
    let north: Double
}

extension BBox {
    var latitudeSpan: Double { north - south }
    var longitudeSpan: Double { east - west }

    private var midLatitude: Double { (north + south) / 2.0 }
    private var midLongitude: Double { (east + west) / 2.0 }

    func canSubdivide(minSpan: Double) -> Bool {
        latitudeSpan > minSpan && longitudeSpan > minSpan
    }

    func subdivided() -> [BBox] {
        guard latitudeSpan > 0, longitudeSpan > 0 else { return [] }
        let midLat = midLatitude
        let midLon = midLongitude
        return [
            BBox(west: west, south: south, east: midLon, north: midLat),
            BBox(west: midLon, south: south, east: east, north: midLat),
            BBox(west: west, south: midLat, east: midLon, north: north),
            BBox(west: midLon, south: midLat, east: east, north: north)
        ]
    }
}

enum PlaceAPI {
    private static let supabaseHardLimit = 1000
    private static let subdivisionDepthLimit = 3
    private static let minimumSubdivisionSpan: Double = 0.01
    private static let minimumRequestedLimit = 100

    static func getPlaces(bbox: BBox, category: String = "all", limit: Int = 750) async throws -> [PlaceDTO] {
        var accumulator: [UUID: PlaceDTO] = [:]
        let sanitizedLimit = sanitize(limit)
        try await collectPlaces(bbox: bbox, category: category, limit: sanitizedLimit, depth: 0, accumulator: &accumulator)
        return sortPlaces(Array(accumulator.values))
    }

    static func saveApplePlaceID(for placeID: UUID, applePlaceID: String) async throws -> Bool {
        let params = SaveApplePlaceIDParams(placeID: placeID, applePlaceID: applePlaceID)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(params)

        let request = try makeRequest(body: payload, endpoint: "rest/v1/rpc/save_apple_place_id")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        let rpcResponse = try decoder.decode([SaveApplePlaceIDResponse].self, from: data)
        return !rpcResponse.isEmpty
    }

    static func searchPlaces(matching query: String, limit: Int = 40) async throws -> [PlaceDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let resolvedLimit = max(1, min(limit, supabaseHardLimit))
        let encodedQuery = trimmed.replacingOccurrences(of: "*", with: "")
        let likePattern = "*\(encodedQuery)*"

        let selectColumns = "id,name,category,lat,lon,address,halal_status,rating,rating_count,confidence,source,apple_place_id"

        let queryItems = [
            URLQueryItem(name: "select", value: selectColumns),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "rating.desc.nullslast"),
            URLQueryItem(name: "limit", value: "\(resolvedLimit)"),
            URLQueryItem(name: "or", value: "(name.ilike.\(likePattern),address.ilike.\(likePattern))")
        ]

        let request = try makeGETRequest(path: "rest/v1/place", queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
#if DEBUG
            if let bodyString = String(data: data, encoding: .utf8) {
                print("Supabase search error", httpResponse.statusCode, bodyString)
            } else {
                print("Supabase search error", httpResponse.statusCode)
            }
#endif
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([PlaceDTO].self, from: data)
    }

    private static func collectPlaces(
        bbox: BBox,
        category: String,
        limit: Int,
        depth: Int,
        accumulator: inout [UUID: PlaceDTO]
    ) async throws {
        let page = try await fetchPlacesPage(bbox: bbox, category: category, limit: limit)
        for dto in page {
            accumulator[dto.id] = dto
        }

        let hitLimit = page.count >= limit
        guard hitLimit,
              depth < subdivisionDepthLimit,
              bbox.canSubdivide(minSpan: minimumSubdivisionSpan) else {
            return
        }

        // Supabase truncates results per request; split the bounding box to surface densely clustered places.
        for subBox in bbox.subdivided() {
            try await collectPlaces(bbox: subBox, category: category, limit: limit, depth: depth + 1, accumulator: &accumulator)
        }
    }

    private static func fetchPlacesPage(bbox: BBox, category: String, limit: Int) async throws -> [PlaceDTO] {
        let resolvedLimit = sanitize(limit)
        let params = GetPlacesParams(
            west: bbox.west,
            south: bbox.south,
            east: bbox.east,
            north: bbox.north,
            cat: category,
            maxCount: resolvedLimit
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(params)

        let request = try makeRequest(body: payload, endpoint: "rest/v1/rpc/get_places_in_bbox")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
#if DEBUG
            if let bodyString = String(data: data, encoding: .utf8) {
                print("Supabase RPC error", httpResponse.statusCode, bodyString)
            } else {
                print("Supabase RPC error", httpResponse.statusCode)
            }
#endif
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([PlaceDTO].self, from: data)
        return rows
    }

    private static func sanitize(_ requested: Int) -> Int {
        let clamped = min(max(requested, minimumRequestedLimit), supabaseHardLimit)
        return max(1, clamped)
    }

    private static func sortPlaces(_ places: [PlaceDTO]) -> [PlaceDTO] {
        places.sorted { lhs, rhs in
            switch (lhs.rating, rhs.rating) {
            case let (l?, r?) where l != r:
                return l > r
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }

            switch (lhs.confidence, rhs.confidence) {
            case let (l?, r?) where l != r:
                return l > r
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }

            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName != rhsName {
                return lhsName < rhsName
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func makeRequest(body: Data, endpoint: String) throws -> URLRequest {
        let baseURL = Env.url
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PlaceAPIError.invalidURL
        }

        var path = components.path
        if !path.hasSuffix("/") { path.append("/") }
        path.append(endpoint)
        components.path = path

        guard let url = components.url else {
            throw PlaceAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("params=single-object", forHTTPHeaderField: "Prefer")
        let apiKey = Env.anonKey
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func makeGETRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        let baseURL = Env.url
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PlaceAPIError.invalidURL
        }

        var builtPath = components.path
        if !builtPath.hasSuffix("/") { builtPath.append("/") }
        builtPath.append(path)
        components.path = builtPath
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlaceAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let apiKey = Env.anonKey
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("public", forHTTPHeaderField: "Accept-Profile")
        return request
    }
}

private struct GetPlacesParams: Encodable, Sendable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double
    let cat: String
    let maxCount: Int

    enum CodingKeys: String, CodingKey {
        case west, south, east, north
        case cat
        case maxCount = "max_count"
    }
}

private struct SaveApplePlaceIDParams: Encodable, Sendable {
    let placeID: UUID
    let applePlaceID: String

    enum CodingKeys: String, CodingKey {
        case placeID = "p_place_id"
        case applePlaceID = "p_apple_place_id"
    }
}

private struct SaveApplePlaceIDResponse: Decodable {
    let id: UUID
    let apple_place_id: String
}

enum PlaceAPIError: Error {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, body: String?)
}
