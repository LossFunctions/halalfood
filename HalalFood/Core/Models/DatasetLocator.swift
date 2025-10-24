import Foundation

enum DatasetLocatorError: Error, LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Dataset CSV not found in app bundle (default.csv or yelp_halal.csv)."
        }
    }
}

/// Centralized lookup for the initial dataset CSV.
/// Tries `default.csv` first, then falls back to `yelp_halal.csv`.
struct DatasetLocator {
    static func datasetURL(in bundle: Bundle = .main) throws -> URL {
        if let url = bundle.url(forResource: "default", withExtension: "csv") {
            return url
        }
        if let url = bundle.url(forResource: "yelp_halal", withExtension: "csv") {
            return url
        }
        throw DatasetLocatorError.notFound
    }
}

