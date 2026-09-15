import Foundation
import Supabase

nonisolated enum SupabaseConfig: Sendable {
    static var current: SupabaseClient? {
        guard let url = value(for: "SUPABASE_URL").flatMap(URL.init(string:)),
              let key = value(for: "SUPABASE_KEY"),
              !key.isEmpty
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    private static func value(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let value = dict[key] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
