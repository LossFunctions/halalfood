import Foundation
import Supabase

enum Env {
    static var url: URL {
        if let cached = cachedURL { return cached }
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let environmentValue = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let string = (bundleValue?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (environmentValue?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        guard let string else {
            fatalError("SUPABASE_URL missing. Provide it via Info.plist or the SUPABASE_URL environment variable.")
        }
        guard let url = URL(string: string) else {
            fatalError("SUPABASE_URL missing or invalid. Provide it via Info.plist or environment variable.")
        }
        cachedURL = url
        return url
    }

    static var anonKey: String {
        if let cached = cachedAnonKey { return cached }
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !bundleKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedAnonKey = bundleKey
            return bundleKey
        }
        if let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envKey.isEmpty {
            cachedAnonKey = envKey
            return envKey
        }
        fatalError("SUPABASE_ANON_KEY missing. Provide it via Info.plist or the SUPABASE_ANON_KEY environment variable.")
    }

    static var displayLocationV2Enabled: Bool {
        if let cached = cachedDisplayLocationV2Enabled { return cached }
        let resolved = resolveBooleanFlag(infoKey: "DISPLAY_LOCATION_V2_ENABLED",
                                          envKey: "DISPLAY_LOCATION_V2_ENABLED",
                                          defaultValue: true)
        cachedDisplayLocationV2Enabled = resolved
        return resolved
    }

    private static var cachedURL: URL?
    private static var cachedAnonKey: String?
    private static var cachedDisplayLocationV2Enabled: Bool?

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
