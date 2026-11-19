import Supabase
import Testing
@testable import Kohi

/// A second client, built and dropped, crashes Auth while its session refresh
/// is still in flight.
struct SupabaseConfigTests {
    @Test func everyCallerSharesOneClient() {
        let first = SupabaseConfig.current
        let second = SupabaseConfig.current
        #expect(first === second)
    }
}
