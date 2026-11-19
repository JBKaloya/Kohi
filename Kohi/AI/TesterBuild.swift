import Foundation
import StoreKit

/// Whether this copy of the app is a tester's: a Debug build, or one
/// installed from TestFlight. The App Store build answers no, so what is
/// gated on it never reaches a customer.
@MainActor
enum TesterBuild {
    #if DEBUG
    private(set) static var isTester = true
    #else
    private(set) static var isTester = false
    #endif

    /// TestFlight builds are signed by the sandbox environment. Called once
    /// at launch; until it answers, a release build is not a tester's.
    static func resolve() async {
        #if !DEBUG
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result
        else { return }
        isTester = transaction.environment != .production
        #endif
    }
}
