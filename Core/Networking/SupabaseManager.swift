import Foundation
import Supabase

enum Env {
    static var url: URL {
        if let cached = cachedURL { return cached }
        guard let url = optionalURL() else {
            fatalError("SUPABASE_URL missing. Provide it via Info.plist or the SUPABASE_URL environment variable.")
        }
        return url
    }

    static var anonKey: String {
        if let cached = cachedAnonKey { return cached }
        guard let key = optionalAnonKey() else {
            fatalError("SUPABASE_ANON_KEY missing. Provide it via Info.plist or the SUPABASE_ANON_KEY environment variable.")
        }
        return key
    }

    static var displayLocationV2Enabled: Bool {
        if let cached = cachedDisplayLocationV2Enabled { return cached }
        let resolved = resolveBooleanFlag(infoKey: "DISPLAY_LOCATION_V2_ENABLED",
                                          envKey: "DISPLAY_LOCATION_V2_ENABLED",
                                          defaultValue: true)
        cachedDisplayLocationV2Enabled = resolved
        return resolved
    }

    static var googleMapsAPIKey: String? {
        if let cached = cachedGoogleMapsAPIKey { return cached }
        let resolved = resolveStringValue(infoKey: "GOOGLE_MAPS_API_KEY", envKey: "google_maps_api_key")
            ?? resolveStringValue(infoKey: "GOOGLE_MAPS_API_KEY", envKey: "GOOGLE_MAPS_API_KEY")
        cachedGoogleMapsAPIKey = resolved
        return resolved
    }

    static func optionalURL() -> URL? {
        if let cached = cachedURL { return cached }
        guard let string = resolvedURLString(), let url = URL(string: string) else { return nil }
        cachedURL = url
        return url
    }

    static func optionalAnonKey() -> String? {
        if let cached = cachedAnonKey { return cached }
        guard let key = resolvedAnonKey(), !key.isEmpty else { return nil }
        cachedAnonKey = key
        return key
    }

    private static var cachedURL: URL?
    private static var cachedAnonKey: String?
    private static var cachedDisplayLocationV2Enabled: Bool?
    private static var cachedGoogleMapsAPIKey: String?

    private static func resolvedURLString() -> String? {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let environmentValue = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        return (bundleValue?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (environmentValue?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func resolvedAnonKey() -> String? {
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
            let trimmed = bundleKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    private static func resolveStringValue(infoKey: String, envKey: String) -> String? {
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let envValue = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
        }
        return nil
    }

    private static func resolveBooleanFlag(infoKey: String, envKey: String, defaultValue: Bool) -> Bool {
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: infoKey) {
            if let boolValue = bundleValue as? Bool { return boolValue }
            if let stringValue = bundleValue as? String, let parsed = parseBooleanFlag(stringValue) {
                return parsed
            }
        }
        if let envValue = ProcessInfo.processInfo.environment[envKey], let parsed = parseBooleanFlag(envValue) {
            return parsed
        }
        return defaultValue
    }

    private static func parseBooleanFlag(_ raw: String) -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "true", "1", "yes", "y", "on":
            return true
        case "false", "0", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        let supabaseURL = Env.url
        let supabaseKey = Env.anonKey

#if DEBUG
        print("Supabase URL:", supabaseURL.absoluteString)
        let keyPreview = supabaseKey.isEmpty ? "" : String(supabaseKey.prefix(6)) + "…"
        print("Supabase anon key present:", !supabaseKey.isEmpty, "preview:", keyPreview)
#endif

        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
}
