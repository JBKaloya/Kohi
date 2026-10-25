import Foundation

/// Session memory for model answers that fire on a sheet opening themselves.
///
/// Ask, dictation and label reading are user-started and a new payload each
/// time; they stay uncached. Suggested correction and recipe variants were
/// spending a generate on every reopen of the same After or recipe sheet.
@MainActor
enum AICallCache {
    private static var suggested: [String: SuggestedCorrection] = [:]
    private static var variants: [String: RecipeAdapt.Variant] = [:]
    private static var emptyVariants: Set<String> = []

    static func suggested(for key: String) -> SuggestedCorrection? {
        suggested[key]
    }

    static func store(_ value: SuggestedCorrection, for key: String) {
        suggested[key] = value
    }

    static func variant(for key: String) -> RecipeAdapt.Variant? {
        variants[key]
    }

    static func hasEmptyVariant(for key: String) -> Bool {
        emptyVariants.contains(key)
    }

    static func store(_ value: RecipeAdapt.Variant, for key: String) {
        variants[key] = value
        emptyVariants.remove(key)
    }

    static func storeEmptyVariant(for key: String) {
        emptyVariants.insert(key)
        variants.removeValue(forKey: key)
    }

    private static var transcripts: [String: String] = [:]

    static func transcript(for key: String) -> String? {
        transcripts[key]
    }

    static func storeTranscript(_ value: String, for key: String) {
        transcripts[key] = value
    }

    static func reset() {
        suggested.removeAll()
        variants.removeAll()
        emptyVariants.removeAll()
        transcripts.removeAll()
    }
}
