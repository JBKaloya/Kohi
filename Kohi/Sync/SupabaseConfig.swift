import Foundation
import Supabase

/// The one Supabase client for the process.
///
/// Each client registers its auth dependencies under a fresh id and removes
/// them in `deinit`, while the session refresh it just started is still
/// running. A client made for one call and then dropped hits
/// `Dependencies not found for id` and takes the app down. Callers that only
/// check `current != nil` used to do exactly that.
nonisolated enum SupabaseConfig: Sendable {
    static var current: SupabaseClient? { client }

    /// Built once. A second construction, even one that loses a race and is
    /// immediately released, is the crash above.
    private static let client: SupabaseClient? = {
        guard let url = value(for: "SUPABASE_URL").flatMap(URL.init(string:)),
              let key = value(for: "SUPABASE_KEY"),
              !key.isEmpty
        else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }()

    private static func value(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let value = dict[key] as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
