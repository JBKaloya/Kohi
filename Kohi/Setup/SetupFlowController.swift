import Foundation
import Observation
import SwiftUI

/// When the post-scan onboarding sheet is showing, and the two flags that
/// decide whether it ever shows itself.
@Observable
@MainActor
final class SetupFlowController {
    var isPresented = false

    private static let seenKey = "setup.hasSeenSetupFlow"
    private static let scannedKey = "setup.hasScannedFirstCard"

    var hasSeenSetupFlow: Bool {
        get { UserDefaults.standard.bool(forKey: Self.seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.seenKey) }
    }

    var hasScannedFirstCard: Bool {
        get { UserDefaults.standard.bool(forKey: Self.scannedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.scannedKey) }
    }

    /// First real scan saved. After the landing window, the sheet comes up
    /// once, and never again unless the user asks from Profile.
    func noteFirstScanSaved() {
        guard !hasScannedFirstCard else { return }
        hasScannedFirstCard = true
        guard !hasSeenSetupFlow else { return }
        Task {
            try? await Task.sleep(for: Motion.Tile.landingWindow)
            isPresented = true
        }
    }

    func dismissed() {
        hasSeenSetupFlow = true
        isPresented = false
    }

    func resetFirstScanFlag() {
        hasScannedFirstCard = false
        hasSeenSetupFlow = false
    }
}
