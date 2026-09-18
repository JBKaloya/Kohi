import Foundation

/// User-facing copy that the vocabulary test greps. Coffee process "Washed"
/// stays a process name; the scan button is Whiten.
nonisolated enum Copy {
    static let coffees = "Coffees"
    static let recipes = "Recipes"
    static let whiten = "Whiten"
    static let whitenHint = "Whiter paper, sharper text"
    static let suggestedCorrection = "Suggested correction"
    static let forYourGrinder = "For your grinder"
    static let dictate = "Dictate"
    static let fromThePros = "From the pros"
    static let features = "Features"
    static let coffeeDose = "Coffee dose"
    static let waterWeight = "Water weight"
    static let beverage = "Beverage"
    static let roastedOn = "Roasted on"
    static let boughtAt = "Bought at"
    static let onTheBag = "On the bag"
    static let noteToSelf = "Note to self"
    static let brewAgain = "Brew again"
    static let compare = "Compare"
    static let filters = "Filters"
    static let newRecipe = "New recipe"
    static let totalBrewTime = "Total brew time"
    static let dictationUnavailable = "Dictation unavailable"
    static let whatYoureDoing = "What you're doing"
    static let suggestedEmpty = "Every coffee has a brew. Scan a new one and it will show up here."
    static let addGrinder = "Add your grinder to see this in clicks"
    static let noClickRange = "No click range on file for this grinder yet"
}

nonisolated extension String {
    /// First letter up, the rest as written. Used for diagnostic sentences.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
