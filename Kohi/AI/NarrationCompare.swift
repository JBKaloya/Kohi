import Foundation

/// Testers compare every way of hearing a Live note on their own brews: the
/// iPhone's reading and each cloud pipeline, shown blind and shuffled. What
/// they pick, and what they would change, decides which pipeline ships.
nonisolated enum NarrationCompare {
    /// Debug or TestFlight, the server switch and yours, and dictations
    /// shared: the audio goes to every provider being compared.
    @MainActor
    static func isEnabled(flags: AIFlags, sharing: Bool) -> Bool {
        TesterBuild.isTester && NarrationAudio.isAllowed(flags: flags, sharing: sharing)
            && flags.isOn(.narrationCompare)
    }
}
