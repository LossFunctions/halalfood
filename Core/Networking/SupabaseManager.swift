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

    private static var cachedURL: URL?
    private static var cachedAnonKey: String?
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
