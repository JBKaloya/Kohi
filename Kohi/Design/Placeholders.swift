import Foundation

/// Real examples, never instructions. One value per field, used everywhere
/// that field appears so a placeholder stays recognisable as an example.
///
/// A placeholder is never written into the model.
nonisolated enum Placeholders {
    enum Field: String, CaseIterable, Sendable {
        case grinderBrand
        case grinderModel
        case grinderUnit
        case grinderRange
        case brewerBrand
        case brewerModel
        case brewerFilter
        case espressoBrand
        case espressoModel
        case espressoBasket
        case espressoPressure
        case kettleBrand
        case kettleModel
        case scaleBrand
        case scaleModel
        case scaleResolution
        case accessoryName
        case accessoryNotes
        case waterName
        case waterTDS
        case waterCalcium
        case waterMagnesium
        case waterSodium
        case waterBicarbonate
        case additiveProduct
        case additiveDose
        case cardCoffee
        case cardRoaster
        case cardCountry
        case cardRegion
        case cardProducer
        case cardAltitude
        case cardVariety
        case cardProcess
        case bagPrice
        case bagWeight
        case bagLot
        case bagHarvest
        case bagCupping
        case bagLink
        case cardPlace
        case cardTastingNotes
        case cardNoteToSelf
        case brewDose
        case brewWater
        case brewBeverage
        case brewTemperature
        case brewTime
        case brewGrind
        case brewTDS
        case brewNotes
        case stepAction
        case stepMass
        case stepTime
        case stepNote
        case recipeName
        case recipeNotes
        case roasterName
        case roasterCity
        case roasterCountry
        case roasterWebsite
        case roasterInstagram
        case askQuestion
        case searchQuery
    }

    static func text(_ field: Field) -> String { table[field]! }

    /// The field's on-screen label, used by the conformance test so a placeholder
    /// never just repeats the name of the box it sits in.
    static func label(_ field: Field) -> String {
        switch field {
        case .grinderBrand, .brewerBrand, .espressoBrand, .kettleBrand, .scaleBrand: "Brand"
        case .grinderModel, .brewerModel, .espressoModel, .kettleModel, .scaleModel: "Model"
        case .grinderUnit: "Setting unit"
        case .grinderRange: "Range"
        case .brewerFilter: "Filter"
        case .espressoBasket: "Basket"
        case .espressoPressure: "Pressure"
        case .scaleResolution: "Resolution"
        case .accessoryName: "Name"
        case .accessoryNotes, .cardNoteToSelf, .brewNotes, .recipeNotes: "Notes"
        case .waterName: "Name"
        case .waterTDS, .brewTDS: "TDS"
        case .waterCalcium: "Calcium"
        case .waterMagnesium: "Magnesium"
        case .waterSodium: "Sodium"
        case .waterBicarbonate: "Bicarbonate"
        case .additiveProduct: "Product"
        case .additiveDose: "Dose"
        case .cardCoffee: "Coffee"
        case .cardRoaster: "Roaster"
        case .cardCountry, .roasterCountry: "Country"
        case .cardRegion: "Region"
        case .cardProducer: "Producer"
        case .cardAltitude: "Altitude"
        case .cardVariety: "Variety"
        case .cardProcess: "Process"
        case .bagPrice: "Price"
        case .bagWeight: "Bag"
        case .bagLot: "Lot"
        case .bagHarvest: "Harvest"
        case .bagCupping: "Cupping"
        case .bagLink: "Link"
        case .cardPlace: "Place"
        case .cardTastingNotes: "Tasting notes"
        case .brewDose: "Dose"
        case .brewWater: "Water"
        case .brewBeverage: "Beverage"
        case .brewTemperature: "Temperature"
        case .brewTime: "Time"
        case .brewGrind: "Grind"
        case .stepAction: "Action"
        case .stepMass: "Mass"
        case .stepTime: "Time"
        case .stepNote: "Note"
        case .recipeName: "Name"
        case .roasterName: "Name"
        case .roasterCity: "City"
        case .roasterWebsite: "Website"
        case .roasterInstagram: "Instagram"
        case .askQuestion: "Question"
        case .searchQuery: "Query"
        }
    }

    private static let table: [Field: String] = [
        .grinderBrand: "Comandante",
        .grinderModel: "C40 MK4",
        .grinderUnit: "clicks",
        .grinderRange: "espresso 8–12 · V60 20–26",
        .brewerBrand: "Hario",
        .brewerModel: "V60 02",
        .brewerFilter: "Cafec Abaca 02",
        .espressoBrand: "Lelit",
        .espressoModel: "Bianca",
        .espressoBasket: "18",
        .espressoPressure: "9",
        .kettleBrand: "Fellow",
        .kettleModel: "Stagg EKG",
        .scaleBrand: "Timemore",
        .scaleModel: "Black Mirror Nano",
        .scaleResolution: "0.1",
        .accessoryName: "WDT tool",
        .accessoryNotes: "Normcore, 0.35 mm",
        .waterName: "Volvic",
        .waterTDS: "130",
        .waterCalcium: "12",
        .waterMagnesium: "8",
        .waterSodium: "12",
        .waterBicarbonate: "74",
        .additiveProduct: "Third Wave Water Classic",
        .additiveDose: "1 sachet / 1 L",
        .cardCoffee: "Ethiopia Chelchele – Washed",
        .cardRoaster: "Townsfolk Coffee",
        .cardCountry: "Ethiopia",
        .cardRegion: "Gedeb, Gedeo",
        .cardProducer: "Smallholders",
        .cardAltitude: "1,900–2,100 m",
        .cardVariety: "Heirloom",
        .cardProcess: "Washed",
        .bagPrice: "14",
        .bagWeight: "250",
        .bagLot: "L2409",
        .bagHarvest: "2025/26",
        .bagCupping: "86.5",
        .bagLink: "townsfolkcoffee.com/…",
        .cardPlace: "Townsfolk Coffee, Tokyo",
        .cardTastingNotes: "Bergamot, black tea",
        .cardNoteToSelf: "Bought after the Kyoto trip",
        .brewDose: "15",
        .brewWater: "250",
        .brewBeverage: "36",
        .brewTemperature: "94",
        .brewTime: "2:45",
        .brewGrind: "22",
        .brewTDS: "1.35",
        .brewNotes: "Bright, a bit thin — try finer",
        .stepAction: "Pour",
        .stepMass: "100",
        .stepTime: "0:45",
        .stepNote: "in circles",
        .recipeName: "Sunday V60",
        .recipeNotes: "Works with light washed Ethiopians",
        .roasterName: "Belleville Brûlerie",
        .roasterCity: "Paris",
        .roasterCountry: "France",
        .roasterWebsite: "belleville-brulerie.com",
        .roasterInstagram: "@bellevillebrulerie",
        .askQuestion: "Why is my V60 sour?",
        .searchQuery: "Ethiopia, washed, bergamot",
    ]
}
