import Foundation

/// The seed of a card. Same identifier, same card, on every device and every launch.
/// Never `hashValue`: Swift randomises it per process.
nonisolated enum CardSeed {
    static func fnv1a32(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return h
    }

    static func seed(for id: UUID) -> UInt32 {
        fnv1a32(id.uuidString.lowercased())
    }
}

/// mulberry32, bit for bit with the card lab prototype.
nonisolated struct Mulberry32: Sendable {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func unit() -> Double {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// (unit − 0.5) × 2 × amplitude
    mutating func jitter(_ amplitude: Double) -> Double { (unit() - 0.5) * 2 * amplitude }
}
