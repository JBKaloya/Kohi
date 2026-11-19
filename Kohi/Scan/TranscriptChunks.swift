import Foundation

/// Every chunk Speech heard in a file, not just the last one.
///
/// On-device recognition starts over after a pause: the next result holds
/// only what follows, and the final result only the last utterance. Kept
/// alone, a three-minute narration came back as "Et enfin je termine".
/// Each result is fed here; a result that ends an utterance, or one that
/// starts after the current chunk has ended, settles that chunk.
nonisolated struct TranscriptChunks: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        var at: TimeInterval
        var duration: TimeInterval
        var text: String

        var end: TimeInterval { at + duration }
    }

    /// Timestamps closer than this are the same moment.
    static let tolerance: TimeInterval = 0.05

    private(set) var settled: [Segment] = []
    private(set) var current: [Segment] = []

    /// One recognition result. `endsUtterance` is set when Speech attached
    /// its end-of-speech metadata to it.
    mutating func feed(_ segments: [Segment], endsUtterance: Bool = false) {
        let words = segments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = words.first else { return }

        if Self.isTimed(words) {
            // A result that reaches back over settled chunks is cumulative:
            // it replaces them rather than repeating them.
            settled.removeAll { $0.at >= first.at - Self.tolerance && Self.isTimed([$0]) }
            if let last = current.last, Self.isTimed(current), first.at >= last.end - Self.tolerance,
               first.at > (current.first?.at ?? 0) + Self.tolerance {
                settle()
            }
        } else if Self.startedOver(from: current, to: words) {
            settle()
        }

        current = words
        if endsUtterance { settle() }
    }

    /// Everything heard, in order.
    var segments: [Segment] { settled + current }

    var text: String {
        segments.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var end: TimeInterval { segments.map(\.end).max() ?? 0 }

    private mutating func settle() {
        settled.append(contentsOf: current)
        current = []
    }

    private static func isTimed(_ segments: [Segment]) -> Bool {
        segments.contains { $0.at > 0 || $0.duration > 0 }
    }

    /// Partial results without timestamps: a new chunk shares nothing with
    /// the start of the one before.
    private static func startedOver(from old: [Segment], to new: [Segment]) -> Bool {
        guard old.count >= 2 else { return false }
        let key: ([Segment]) -> [String] = { segments in
            segments.prefix(2).map {
                $0.text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            }
        }
        return key(old) != key(new) && new.count < old.count
    }
}
