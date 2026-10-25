import Foundation

/// Whether an on-device file transcription covered the whole recording.
///
/// Live and server recognition are documented to stop around a minute. On-device
/// file recognition is not, but a short result is still treated as a truncated
/// pass: the remainder is exported and recognised again, at most three times.
nonisolated enum VoiceNoteCoverage {
    static let gapTolerance: TimeInterval = 5
    static let maxPasses = 3

    /// The leftover range of the original file, or nil when the last result
    /// reached the end (within `gapTolerance`).
    static func uncoveredRange(
        coveredThrough: TimeInterval,
        duration: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard duration > 0, duration - coveredThrough > gapTolerance else { return nil }
        let start = min(max(coveredThrough, 0), duration)
        return start...duration
    }

    /// Absolute coverage after a pass whose timestamps are relative to a
    /// trimmed file that started at `origin` in the original recording.
    static func coveredThrough(
        origin: TimeInterval,
        relativeEnd: TimeInterval
    ) -> TimeInterval {
        max(0, origin + relativeEnd)
    }
}
