import Foundation
import os

/// A flavour as stored on a brew: a wheel id, or free text the wheel missed.
nonisolated struct FlavorTag: Codable, Hashable, Sendable, Identifiable {
    /// Wheel id (`fruity-berry-blueberry`) or `custom:<normalised>`.
    var id: String
    /// The words as typed, when this is a custom tag.
    var custom: String?
    /// How strong it was in the cup, 1 (very faint) to 5 (very strong). Nil
    /// until someone says; never set on what a pack announces. An ordinal
    /// step, not a share: five notes can all be strong.
    var intensity: Int?

    var isCustom: Bool { id.hasPrefix("custom:") || custom != nil }

    static let intensities = 1...5

    init(id: String, custom: String? = nil, intensity: Int? = nil) {
        self.id = id
        self.custom = custom
        self.intensity = intensity.flatMap { Self.intensities.contains($0) ? $0 : nil }
    }

    /// The same flavour with no intensity, as it is offered again.
    var unrated: FlavorTag {
        FlavorTag(id: id, custom: custom)
    }

    static func intensityLabel(_ level: Int) -> String {
        switch level {
        case 1: "Very faint"
        case 2: "Faint"
        case 3: "Clear"
        case 4: "Strong"
        default: "Very strong"
        }
    }

    init(custom text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.custom = trimmed
        self.id = "custom:" + FlavorMatcher.normalize(trimmed)
    }

    var displayName: String {
        if let custom, !custom.isEmpty { return custom }
        if isCustom { return String(id.dropFirst("custom:".count)) }
        return FlavorWheel.shared.label(for: id)
    }

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            if text.hasPrefix("custom:") {
                self.id = text
                self.custom = String(text.dropFirst("custom:".count))
            } else if FlavorWheel.shared.node(id: text) != nil {
                self.id = text
                self.custom = nil
            } else {
                let matched = FlavorMatcher.match(text)
                self = matched.tags.first ?? FlavorTag(custom: text)
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        custom = try c.decodeIfPresent(String.self, forKey: .custom)
        intensity = (try? c.decodeIfPresent(Int.self, forKey: .intensity))
            .flatMap { $0 }
            .flatMap { Self.intensities.contains($0) ? $0 : nil }
    }
}

nonisolated extension [FlavorTag] {
    /// Sets the intensity of the tag with this id; nil clears it.
    mutating func setIntensity(_ level: Int?, of id: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].intensity = level.flatMap { FlavorTag.intensities.contains($0) ? $0 : nil }
    }
}

nonisolated enum FlavorOrigin: String, Codable, Sendable {
    case enzymatic
    case sugarBrowning = "sugar-browning"
    case dryDistillation = "dry-distillation"
    case defect
}

nonisolated struct FlavorNode: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var level: Int
    var parent: String?
    var en: String
    var fr: String
    var origin: FlavorOrigin?
    var synonyms: [String]
    var quick: Bool
    var color: String?
    var order: Int?

    var label: String { en }

    enum CodingKeys: String, CodingKey {
        case id, level, parent, en, fr, origin, synonyms, quick, color, order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        level = try c.decode(Int.self, forKey: .level)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        en = try c.decode(String.self, forKey: .en)
        fr = try c.decodeIfPresent(String.self, forKey: .fr) ?? ""
        origin = try c.decodeIfPresent(FlavorOrigin.self, forKey: .origin)
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        quick = try c.decodeIfPresent(Bool.self, forKey: .quick) ?? false
        color = try c.decodeIfPresent(String.self, forKey: .color)
        order = try c.decodeIfPresent(Int.self, forKey: .order)
    }
}

nonisolated struct FlavorWheelDocument: Codable, Sendable {
    var schema: String
    var source: String?
    var licenseNote: String?
    var origins: [String: String]
    var nodes: [FlavorNode]
}

/// The SCA 2016 wheel, bundled, indexed by id and synonym. Never mutated.
nonisolated final class FlavorWheel: Sendable {
    static let shared = FlavorWheel.load()

    let document: FlavorWheelDocument
    let nodes: [FlavorNode]
    private let byID: [String: FlavorNode]
    private let bySynonym: [String: FlavorNode]

    var isEmpty: Bool { nodes.isEmpty }

    var families: [FlavorNode] {
        nodes.filter { $0.level == 1 }.sorted { ($0.order ?? 99) < ($1.order ?? 99) }
    }

    var quick: [FlavorNode] {
        nodes.filter(\.quick)
    }

    func node(id: String) -> FlavorNode? { byID[id] }

    func label(for id: String) -> String {
        byID[id]?.en ?? id
    }

    func origin(for id: String) -> FlavorOrigin? { byID[id]?.origin }

    func originDescription(_ origin: FlavorOrigin) -> String? {
        document.origins[origin.rawValue]
    }

    func children(of id: String) -> [FlavorNode] {
        nodes.filter { $0.parent == id }
    }

    func matchSynonym(_ fragment: String) -> FlavorNode? {
        bySynonym[FlavorMatcher.normalize(fragment)]
    }

    private init(document: FlavorWheelDocument) {
        self.document = document
        self.nodes = document.nodes
        var byID: [String: FlavorNode] = [:]
        var bySynonym: [String: FlavorNode] = [:]
        for node in document.nodes {
            byID[node.id] = node
            for synonym in node.synonyms {
                let key = FlavorMatcher.normalize(synonym)
                if bySynonym[key] == nil { bySynonym[key] = node }
            }
            let en = FlavorMatcher.normalize(node.en)
            if bySynonym[en] == nil { bySynonym[en] = node }
            let fr = FlavorMatcher.normalize(node.fr)
            if bySynonym[fr] == nil { bySynonym[fr] = node }
        }
        self.byID = byID
        self.bySynonym = bySynonym
    }

    private static func load() -> FlavorWheel {
        let empty = FlavorWheelDocument(schema: "", origins: [:], nodes: [])
        guard let url = resourceURL() else {
            Log.app.error("flavor-wheel.json is missing from the bundle")
            return FlavorWheel(document: empty)
        }
        do {
            return FlavorWheel(document: try decode(from: url))
        } catch {
            Log.app.error("could not read flavor-wheel.json: \(error)")
            return FlavorWheel(document: empty)
        }
    }

    static func decode(from url: URL) throws -> FlavorWheelDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FlavorWheelDocument.self, from: data)
    }

    /// Walks to the level-1 family and returns its wheel colour, darkened so
    /// it can be a title on paper. "Red Currant" resolves through Fruity.
    func titleInk(forNote note: String) -> (Double, Double, Double)? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matched = FlavorMatcher.match(trimmed).tags.first { !$0.isCustom }
        let node = matched.flatMap { self.node(id: $0.id) } ?? matchSynonym(trimmed)
        guard let node else { return nil }
        var current = node
        var guardrail = 0
        while current.level != 1, guardrail < 8 {
            guardrail += 1
            guard let parentID = current.parent, let parent = self.node(id: parentID) else { break }
            current = parent
        }
        guard current.level == 1, let hex = current.color else { return nil }
        return Self.darkened(Self.rgb(hex: hex))
    }

    private static func rgb(hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Wheel colours are meant as chips. A title needs them a step darker.
    private static func darkened(_ color: (Double, Double, Double)?) -> (Double, Double, Double)? {
        guard let color else { return nil }
        return (color.0 * 0.62, color.1 * 0.62, color.2 * 0.62)
    }

    private static func resourceURL() -> URL? {
        if let url = Bundle.main.url(forResource: "flavor-wheel", withExtension: "json") {
            return url
        }
        if let url = Bundle(for: FlavorWheel.self).url(forResource: "flavor-wheel", withExtension: "json") {
            return url
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Reference/flavor-wheel.json")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }
}
