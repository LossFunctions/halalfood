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
    struct FetchAllPlacesResponse {
        let places: [PlaceDTO]
        let eTag: String?
        let notModified: Bool
    }

    struct FetchAllPlacePinsResponse {
        let pins: [PlacePinDTO]
        let eTag: String?
        let notModified: Bool
    }

    private static let supabaseHardLimit = 800
    static let mapFetchDefaultLimit = 220
    private static let subdivisionDepthLimit = 3
    private static let minimumSubdivisionSpan: Double = 0.01
    private static let minimumRequestedLimit = 100
    private static var displayLocationV2Enabled: Bool { Env.displayLocationV2Enabled }

    static func getPlaces(bbox: BBox, category: String = "all", limit: Int = mapFetchDefaultLimit) async throws -> [PlaceDTO] {
        let sanitizedLimit = sanitize(limit)
#if DEBUG
        let metadata = String(
            format: "bbox=(%.4f,%.4f,%.4f,%.4f) category=%@ limit=%d",
            bbox.west, bbox.south, bbox.east, bbox.north, category, sanitizedLimit
        )
        let span = PerformanceMetrics.begin(event: .apiGetPlaces, metadata: metadata)
        var resultMetadata = "count=0"
        defer {
            PerformanceMetrics.end(span, metadata: resultMetadata)
        }
#endif
        let accumulator = try await collectPlaces(bbox: bbox, category: category, limit: sanitizedLimit, depth: 0)
        let sorted = sortPlaces(Array(accumulator.values))
        let limited = Array(sorted.prefix(sanitizedLimit))
#if DEBUG
        resultMetadata = "count=\(limited.count)"
#endif
        return limited
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
        let normalized = normalizedSearchQuery(trimmed)

        do {
            return try await searchPlacesViaRPC(query: trimmed, normalizedQuery: normalized, limit: resolvedLimit)
        } catch let error as PlaceAPIError {
            switch error {
            case let .server(statusCode, body) where shouldFallbackToLegacySearch(statusCode: statusCode, body: body):
                return try await searchPlacesViaLegacy(query: trimmed, normalizedQuery: normalized, limit: resolvedLimit)
            case .invalidResponse:
                return try await searchPlacesViaLegacy(query: trimmed, normalizedQuery: normalized, limit: resolvedLimit)
            default:
                throw error
            }
        }
    }

    static func upsertApplePlace(_ payload: ApplePlaceUpsertPayload) async throws -> PlaceDTO {
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)

        let request = try makeRequest(body: body, endpoint: "rest/v1/rpc/upsert_apple_place")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([PlaceDTO].self, from: data)
        if let first = rows.first {
            return first
        }
        throw PlaceAPIError.invalidResponse
    }

    static func fetchAllPlaces(
        limit: Int = 3000,
        pageSize: Int = 800,
        ifNoneMatch: String? = nil
    ) async throws -> FetchAllPlacesResponse {
        let desired = max(1, min(limit, 10_000))
        let size = max(1, min(pageSize, 1000))
        let selectColumns = "id,name,category,lat,lon,address,display_location,halal_status,rating,rating_count,serves_alcohol,source,source_id,external_id,google_place_id,google_match_status,google_maps_url,google_business_status,apple_place_id,note,source_raw"
        let baseQueryItems = [
            URLQueryItem(name: "select", value: selectColumns),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "category", value: "eq.restaurant"),
            URLQueryItem(name: "halal_status", value: "in.(\"yes\",\"only\")"),
            URLQueryItem(name: "order", value: "rating.desc.nullslast")
        ]

        var collected: [PlaceDTO] = []
        var start = 0
        let decoder = JSONDecoder()
        var responseETag: String?
        var receivedNotModified = false
#if DEBUG
        let span = PerformanceMetrics.begin(
            event: .apiFetchAllPlaces,
            metadata: "desired=\(desired) pageSize=\(size)"
        )
        var pageCount = 0
        var resultMetadata = "cancelled-before-start"
#endif

        while start < desired {
            let end = min(start + size - 1, desired - 1)
            var request = try makeGETRequest(path: "rest/v1/place_google_ready", queryItems: baseQueryItems)
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            request.setValue("\(start)-\(end)", forHTTPHeaderField: "Range")
            request.setValue("count=exact", forHTTPHeaderField: "Prefer")
            if start == 0, let ifNoneMatch {
                request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
                request.cachePolicy = .reloadRevalidatingCacheData
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
                PerformanceMetrics.point(
                    event: .apiFetchAllPlaces,
                    metadata: "Invalid response for range \(start)-\(end)"
                )
#endif
                throw PlaceAPIError.invalidResponse
            }

            if httpResponse.statusCode == 304 {
#if DEBUG
                PerformanceMetrics.point(
                    event: .apiFetchAllPlaces,
                    metadata: "HTTP 304 Not Modified for range \(start)-\(end)"
                )
#endif
                receivedNotModified = true
                break
            }

            guard (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
#if DEBUG
                let bodyString = String(data: data, encoding: .utf8) ?? "<unreadable>"
                let metadata = "HTTP \(httpResponse.statusCode) range \(start)-\(end) body=\(bodyString)"
                PerformanceMetrics.point(event: .apiFetchAllPlaces, metadata: metadata)
#endif
                throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
            }

            let page = try decoder.decode([PlaceDTO].self, from: data)
            collected.append(contentsOf: page)
#if DEBUG
            pageCount += 1
            PerformanceMetrics.point(
                event: .apiFetchAllPlaces,
                metadata: "Fetched page \(pageCount) range \(start)-\(end) count=\(page.count)"
            )
#endif

            if responseETag == nil,
               let header = httpResponse.value(forHTTPHeaderField: "ETag") ?? httpResponse.value(forHTTPHeaderField: "Etag") {
                responseETag = header
            }

            if page.count < size { break }
            start += size
        }

        if receivedNotModified {
#if DEBUG
            resultMetadata = "not-modified"
            PerformanceMetrics.point(
                event: .apiFetchAllPlaces,
                metadata: "Supabase returned 304 – using cached dataset"
            )
            PerformanceMetrics.end(span, metadata: resultMetadata)
#endif
            return FetchAllPlacesResponse(places: [], eTag: ifNoneMatch, notModified: true)
        }

#if DEBUG
        resultMetadata = "pages=\(pageCount) total=\(collected.count)"
        PerformanceMetrics.end(span, metadata: resultMetadata)
#endif

        return FetchAllPlacesResponse(places: collected, eTag: responseETag, notModified: false)
    }

    static func fetchAllPlacePins(
        pageSize: Int = 1000,
        ifNoneMatch: String? = nil
    ) async throws -> FetchAllPlacePinsResponse {
        let size = max(1, min(pageSize, 1000))
        let selectColumns = "id,lat,lon,halal_status,updated_at,address"
        let baseQueryItems = [
            URLQueryItem(name: "select", value: selectColumns),
            URLQueryItem(name: "order", value: "id")
        ]

        var collected: [PlacePinDTO] = []
        var start = 0
        let decoder = JSONDecoder()
        var responseETag: String?
        var receivedNotModified = false

        while true {
            let end = start + size - 1
            var request = try makeGETRequest(path: "rest/v1/place_pins", queryItems: baseQueryItems)
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            request.setValue("\(start)-\(end)", forHTTPHeaderField: "Range")
            request.setValue("count=exact", forHTTPHeaderField: "Prefer")
            if start == 0, let ifNoneMatch {
                request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
                request.cachePolicy = .reloadRevalidatingCacheData
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlaceAPIError.invalidResponse
            }

            if httpResponse.statusCode == 304 {
                receivedNotModified = true
                break
            }

            guard (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
            }

            let page = try decoder.decode([PlacePinDTO].self, from: data)
            collected.append(contentsOf: page)

            if responseETag == nil,
               let header = httpResponse.value(forHTTPHeaderField: "ETag") ?? httpResponse.value(forHTTPHeaderField: "Etag") {
                responseETag = header
            }

            if page.count < size { break }
            start += size
        }

        if receivedNotModified {
            return FetchAllPlacePinsResponse(pins: [], eTag: ifNoneMatch, notModified: true)
        }

        return FetchAllPlacePinsResponse(pins: collected, eTag: responseETag, notModified: false)
    }

    static func fetchPlaceDetails(placeID: UUID) async throws -> PlaceDTO? {
        let params = GetPlaceDetailsParams(placeID: placeID)
        let encoder = JSONEncoder()
        let payload = try encoder.encode(params)

        let request = try makeRequest(body: payload, endpoint: "rest/v1/rpc/get_place_details")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([PlaceDTO].self, from: data)
        return rows.first
    }

    static func fetchPlaceDetailsByIDs(_ placeIDs: [UUID]) async throws -> [PlaceDTO] {
        let params = GetPlaceDetailsByIDsParams(placeIDs: placeIDs)
        let encoder = JSONEncoder()
        let payload = try encoder.encode(params)

        let request = try makeRequest(body: payload, endpoint: "rest/v1/rpc/get_place_details_by_ids")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([PlaceDTO].self, from: data)
    }

    static func fetchCommunityTopRated(limitPerRegion: Int = 20) async throws -> [CommunityTopRatedRecord] {
        let params = GetCommunityTopRatedParams(limitPerRegion: limitPerRegion)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try encoder.encode(params)

#if DEBUG
        let span = PerformanceMetrics.begin(
            event: .apiCommunityTopRated,
            metadata: "limitPerRegion=\(limitPerRegion)"
        )
        var resultMetadata = "cancelled"
#endif

        let request = try makeRequest(body: payload, endpoint: "rest/v1/rpc/get_community_top_rated")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
            resultMetadata = "invalid-response"
            PerformanceMetrics.end(span, metadata: resultMetadata)
#endif
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
#if DEBUG
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<unreadable>"
            resultMetadata = "HTTP \(httpResponse.statusCode) body=\(bodyPreview)"
            PerformanceMetrics.end(span, metadata: resultMetadata)
#endif
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([CommunityTopRatedRecord].self, from: data)

#if DEBUG
        resultMetadata = "rows=\(rows.count)"
        PerformanceMetrics.end(span, metadata: resultMetadata)
#endif

        return rows
    }

    private static func collectPlaces(
        bbox: BBox,
        category: String,
        limit: Int,
        depth: Int
    ) async throws -> [UUID: PlaceDTO] {
        try Task.checkCancellation()
        var accumulator: [UUID: PlaceDTO] = [:]
        let page = try await fetchPlacesPage(bbox: bbox, category: category, limit: limit)
        for dto in page {
            accumulator[dto.id] = dto
            if accumulator.count >= limit {
                return accumulator
            }
        }
        try Task.checkCancellation()

        if accumulator.count >= limit {
            return accumulator
        }

        let hitLimit = page.count >= limit
        guard hitLimit,
              depth < subdivisionDepthLimit,
              bbox.canSubdivide(minSpan: minimumSubdivisionSpan) else {
            return accumulator
        }

        let subBoxes = bbox.subdivided()
        guard !subBoxes.isEmpty else { return accumulator }

        return try await withThrowingTaskGroup(of: [UUID: PlaceDTO].self) { group in
            for subBox in subBoxes {
                group.addTask {
                    try Task.checkCancellation()
                    return try await collectPlaces(bbox: subBox, category: category, limit: limit, depth: depth + 1)
                }
            }

            for try await child in group {
                accumulator.merge(child) { existing, _ in existing }
                if accumulator.count >= limit {
                    group.cancelAll()
                    break
                }
            }

            return accumulator
        }
    }

    private static func fetchPlacesPage(bbox: BBox, category: String, limit: Int) async throws -> [PlaceDTO] {
        try Task.checkCancellation()
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

        let endpoint = "rest/v1/rpc/get_places_in_bbox_v3"
        let request = try makeRequest(body: payload, endpoint: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

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

    private static func normalizedSearchQuery(_ query: String) -> String {
        let folded = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(scalars.map(Character.init)).lowercased()
    }

    private static func searchPlacesViaRPC(query: String, normalizedQuery: String, limit: Int) async throws -> [PlaceDTO] {
        let params = SearchPlacesParams(query: query, normalizedQuery: normalizedQuery, limit: limit)
        let encoder = JSONEncoder()
        let body = try encoder.encode(params)

        let endpoint = displayLocationV2Enabled ? "rest/v1/rpc/search_places_v2" : "rest/v1/rpc/search_places"
        let request = try makeRequest(body: body, endpoint: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([PlaceDTO].self, from: data)
    }

    private static func searchPlacesViaLegacy(query: String, normalizedQuery: String, limit: Int) async throws -> [PlaceDTO] {
        let sanitizedLimit = max(1, min(limit, supabaseHardLimit))
        let encodedQuery = query.replacingOccurrences(of: "*", with: "")
        let likePattern = "*\(encodedQuery)*"

        let selectColumns = "id,name,category,lat,lon,address,display_location,halal_status,rating,rating_count,serves_alcohol,source,source_id,external_id,google_place_id,google_match_status,google_maps_url,google_business_status,apple_place_id,note"

        let queryItems = [
            URLQueryItem(name: "select", value: selectColumns),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "halal_status", value: "in.(\"yes\",\"only\")"),
            URLQueryItem(name: "order", value: "rating.desc.nullslast"),
            URLQueryItem(name: "limit", value: "\(sanitizedLimit)"),
            URLQueryItem(name: "or", value: "(name.ilike.\(likePattern),address.ilike.\(likePattern))")
        ]

        let request = try makeGETRequest(path: "rest/v1/place_google_ready", queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaceAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaceAPIError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        return try decoder.decode([PlaceDTO].self, from: data)
    }

    private static func shouldFallbackToLegacySearch(statusCode: Int, body: String?) -> Bool {
        if statusCode == 404 { return true }
        if statusCode == 400 || statusCode == 500 {
            if let body, body.lowercased().contains("search_places") {
                return true
            }
        }
        return false
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

            switch (lhs.rating_count, rhs.rating_count) {
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
        guard let baseURL = Env.optionalURL(),
              let apiKey = Env.optionalAnonKey() else {
            throw PlaceAPIError.missingConfiguration
        }
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
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func makeGETRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard let baseURL = Env.optionalURL(),
              let apiKey = Env.optionalAnonKey() else {
            throw PlaceAPIError.missingConfiguration
        }
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

private struct SearchPlacesParams: Encodable, Sendable {
    let query: String
    let normalizedQuery: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case normalizedQuery = "p_normalized_query"
        case limit = "p_limit"
    }
}

private struct GetPlaceDetailsParams: Encodable, Sendable {
    let placeID: UUID

    enum CodingKeys: String, CodingKey {
        case placeID = "p_place_id"
    }
}

private struct GetPlaceDetailsByIDsParams: Encodable, Sendable {
    let placeIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case placeIDs = "p_place_ids"
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

private struct GetCommunityTopRatedParams: Encodable, Sendable {
    let limitPerRegion: Int
}

enum PlaceAPIError: Error {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, body: String?)
    case missingConfiguration
}
