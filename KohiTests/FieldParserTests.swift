import CoreGraphics
import Testing
@testable import Kohi

/// Fixtures transcribed from real cards in the reference archive. Each test
/// feeds the parser the lines OCR produces for that card and pins down the
/// fields it must extract.
struct FieldParserTests {
    private func lines(_ texts: [String]) -> [TextExtractor.Line] {
        texts.enumerated().map { index, text in
            TextExtractor.Line(text: text, y: Double(index) * 0.03, x: 0)
        }
    }

    // MARK: - Label/value layouts

    @Test func kloverLabelValueCard() {
        let parsed = FieldParser.parse(lines([
            "KLOVER COFFEE PARIS",
            "Ethiopia Nano Challa",
            "Region : Geera, Jimma",
            "Altitude : 2048 Masl",
            "Variety : Heirloom",
            "Process : Washed",
            "Note : Floral , Citrus , Stonefruits",
            "Coffee roasted in Paris, France",
            "250g",
        ]))

        #expect(parsed.region == "Geera, Jimma")
        #expect(parsed.altitude == "2048 Masl")
        #expect(parsed.variety == "Heirloom")
        #expect(parsed.process == "Washed")
        #expect(parsed.tastingNotes == ["Floral", "Citrus", "Stonefruits"])
        #expect(parsed.country == "Ethiopia")
    }

    @Test func juneTwoColumnCard() {
        let parsed = FieldParser.parse(lines([
            "KE", "Q 87",
            "Notes:",
            "Floral", "Red Currant", "Vanilla",
            "Farmer:", "Tekangu Cooperative",
            "Region:", "Nyeri, Kenya",
            "Altitude:", "1800m",
            "Variety:", "AA Tekangu Ngunguru #101",
            "Process:", "Washed",
            "Kenya Tekangu comes from the high slopes of Mount Kenya where smallholder farmers hand-pick",
        ]))

        #expect(parsed.tastingNotes == ["Floral", "Red Currant", "Vanilla"])
        #expect(parsed.producer == "Tekangu Cooperative")
        #expect(parsed.region == "Nyeri")
        #expect(parsed.country == "Kenya")
        #expect(parsed.altitude == "1800m")
        #expect(parsed.variety == "AA Tekangu Ngunguru #101")
        #expect(parsed.process == "Washed")
    }

    @Test func bonanzaPipeSeparatedCard() {
        let parsed = FieldParser.parse(lines([
            "BONANZA COFFEE",
            "ROASTERS",
            "Karimikui AA",
            "Kenya",
            "TANGERINE | BLACKCURRANT | VANILLA",
            "PRODUCER: RUNGETO FCS",
            "VARIETAL: SL-28. SL-34 | PROCESS: WASHED",
            "250g - 8.8oz",
        ]))

        #expect(parsed.producer == "RUNGETO FCS")
        #expect(parsed.variety == "SL-28. SL-34")
        #expect(parsed.process == "WASHED")
        #expect(parsed.country == "Kenya")
        #expect(parsed.tastingNotes == ["TANGERINE", "BLACKCURRANT", "VANILLA"])
    }

    @Test func townsfolkBracketedLabelsOnOneLine() {
        let parsed = FieldParser.parse(lines([
            "townsfolk",
            "Ethiopia Chelchele",
            "[Process]Washed [Variety]Heirloom",
            "Gedeb, Gedeo",
        ]))

        #expect(parsed.process == "Washed")
        #expect(parsed.variety == "Heirloom")
    }

    @Test func dotcomLowercaseLabels() {
        let parsed = FieldParser.parse(lines([
            "ETHIOPIA",
            "guji g-1 anasora",
            "variety", "Heirloom",
            "process", "natural",
            "elevation", "1900 - 1950m",
            "flavor", "buleberry / red wine / plum", "clean / smooth",
            "dotcom coffee",
        ]))

        #expect(parsed.variety == "Heirloom")
        #expect(parsed.process == "natural")
        #expect(parsed.altitude == "1900 - 1950m")
        #expect(parsed.country == "Ethiopia")
        #expect(parsed.tastingNotes == ["buleberry", "red wine", "plum", "clean", "smooth"])
    }

    @Test func quoRemindsUsOfNotes() {
        let parsed = FieldParser.parse(lines([
            "Brazil",
            "Serra do Caracol",
            "Producer", "Leonardo and Paulo Teixeira",
            "Variety", "Yellow Catuai",
            "Process", "Natural",
            "Reminds us of",
            "Roasted Almonds", "Yellow Plums", "Milk Chocolate",
        ]))

        #expect(parsed.producer == "Leonardo and Paulo Teixeira")
        #expect(parsed.variety == "Yellow Catuai")
        #expect(parsed.process == "Natural")
        #expect(parsed.country == "Brazil")
        #expect(parsed.tastingNotes == ["Roasted Almonds", "Yellow Plums", "Milk Chocolate"])
    }

    // MARK: - Parenthesised token layout

    @Test func beanroomTokenCard() {
        let parsed = FieldParser.parse(lines([
            "BOLIVIA",
            "(B)",
            "( Caranavi )",
            "( Alasitas ) ( Gesha )",
            "( 1600m ) ( Double Fermentation )",
            "LIGHT",
            "( Yuzu ) ( Blooming Jasmine )",
            "( Fresh Cranberry ) ( Vanilla Cream )",
            "• Filter",
        ]))

        #expect(parsed.country == "Bolivia")
        #expect(parsed.region == "Caranavi")
        #expect(parsed.producer == "Alasitas")
        #expect(parsed.variety == "Gesha")
        #expect(parsed.altitude == "1600m")
        #expect(parsed.process == "Double Fermentation")
        #expect(parsed.tastingNotes == ["Yuzu", "Blooming Jasmine", "Fresh Cranberry", "Vanilla Cream"])
    }

    @Test func decorativeParenthesesAreNotTokens() {
        let parsed = FieldParser.parse(lines([
            "ROASTER",
            "CODE BLACK COFFEE ROASTERS",
            "(Melbourne, Australia)",
            "COUNTRY", "Colombia",
            "FARM", "Las Margaritas",
            "VARIETY", "Pacamara",
            "PROCESS", "Natural",
            "ELEVATION", "1,570~1,850m",
            "FLAVOR", "Grape Candy, Papaya, Cacao",
        ]))

        #expect(parsed.roaster == "CODE BLACK COFFEE ROASTERS")
        #expect(parsed.country == "Colombia")
        #expect(parsed.producer == "Las Margaritas")
        #expect(parsed.variety == "Pacamara")
        #expect(parsed.process == "Natural")
        #expect(parsed.altitude == "1,570~1,850m")
        #expect(parsed.tastingNotes == ["Grape Candy", "Papaya", "Cacao"])
    }

    // MARK: - French

    @Test func momusFrenchCard() {
        let parsed = FieldParser.parse(lines([
            "Bourbon Rouge",
            "Café Grand Cru",
            "Edition Pure Origine",
            "Agriculture biologique",
            "Torréfaction française, artisanale, biologique",
            "Procédé de séchage lavé",
            "Idéal pour un expresso ou une méthode douce",
            "Intensité équilibrée",
            "Texture ronde et satinée",
            "Miel", "Chocolat", "Lemongrass",
            "Espèce Arabica — Variété Bourbon Rouge",
            "Rwanda - Gakenke",
            "Coopérative Dukundekawa",
            "Altitude 2 000 mètres",
            "@MOMUS.PARIS",
        ]))

        #expect(parsed.variety == "Bourbon Rouge")
        #expect(parsed.producer == "Dukundekawa")
        #expect(parsed.altitude == "2 000 mètres")
        #expect(parsed.country == "Rwanda")
        #expect(parsed.process == "Washed")
        #expect(parsed.originalFields["process"] == "de séchage lavé")
        // Prose with commas must not leak into the notes.
        #expect(!parsed.tastingNotes.contains("artisanale"))
    }

    // MARK: - Japanese

    @Test func japaneseBagLabels() {
        let parsed = FieldParser.parse(lines([
            "BLEND No.01", "ORIGINAL",
            "名称", "レギュラーコーヒー",
            "原材料名", "コーヒー豆",
            "生豆生産国", "Brazil", "El Salvador", "Uganda", "Ethiopia",
            "内容量", "200g",
            "保存方法", "高温多湿,直射日光を避け保存してください。",
        ]))

        #expect(parsed.sourceLanguage == "ja")
        #expect(parsed.name == "レギュラーコーヒー")
        #expect(parsed.country == "Brazil")
    }

    // MARK: - Chinese, handwritten layout

    @Test func linChineseCard() throws {
        let parsed = FieldParser.parse(lines([
            "LIN 巴浪树林",
            "产地: 厄瓜多尔",
            "豆种: 改良铁皮卡",
            "处理: 水洗",
            "风味: 白花、柠檬、红提、乌龙茶",
            "萃取参数",
            "滤杯: 三段式",
            "粉重", "15 g",
            "注水量: 220g",
            "研磨度: EK#14",
            "冲煮用水: AQ98PPM",
            "①滴滤/浸泡 30 100克 92℃",
        ]))

        #expect(parsed.sourceLanguage == "zh")
        #expect(parsed.country == "Ecuador")
        #expect(parsed.originalFields["country"] == "厄瓜多尔")
        #expect(parsed.variety == "Typica")
        #expect(parsed.originalFields["variety"] == "改良铁皮卡")
        #expect(parsed.process == "Washed")
        #expect(parsed.originalFields["process"] == "水洗")
        #expect(parsed.tastingNotes == ["白花", "柠檬", "红提", "乌龙茶"])

        let recipe = try #require(parsed.recipe)
        #expect(recipe.dose == 15)
        #expect(recipe.water == 220)
        #expect(recipe.grind.display() == "EK#14")
        #expect(recipe.method == .filter)
    }

    // MARK: - Note hygiene

    @Test func bagChromeStaysOutOfNotes() {
        let parsed = FieldParser.parse(lines([
            "BLUE BOTTLE COFFEE",
            "THREE AFRICAS",
            "TASTING NOTES",
            "Golden Raisin", "Winey Blueberry", "Lemon Zest",
            "USDA ORGANIC",
            "WHOLE BEAN COFFEE",
            "NET WT 12 OZ (340g)",
        ]))

        #expect(parsed.tastingNotes == ["Golden Raisin", "Winey Blueberry", "Lemon Zest"])
    }

    /// OCR reads "ELEVATION" as "eievation" and "VARIETY" as "VARIET T". Both
    /// are labels, and neither may become the value of the label above it.
    @Test func mangledLabelsAreNotValues() {
        let parsed = FieldParser.parse(lines([
            "process", "eievation", "1900m",
            "PRODUCER", "VARIET T", "Pacamara",
        ]))

        #expect(parsed.process == nil)
        #expect(parsed.producer == nil)
    }

    @Test func proseAfterALabelIsNotAValue() {
        let parsed = FieldParser.parse(lines([
            "Coffee roasted in Paris, France",
            "Region : Geera",
        ]))

        #expect(parsed.name == nil)
        #expect(parsed.region == "Geera")
    }

    /// The country field has a closed vocabulary, so a misread is a miss.
    @Test func unrecognisedCountryIsDropped() {
        let parsed = FieldParser.parse(lines(["COUNTRY", "121/", "VARIETY", "Gesha"]))

        #expect(parsed.country == nil)
        #expect(parsed.variety == "Gesha")
    }

    /// Japanese packaging labels all end in 名 / 量 / 法 / 日, and OCR mangles
    /// their stems: "密材料名" for 原材料名.
    @Test func packagingLabelsAreNotNames() {
        let parsed = FieldParser.parse(lines([
            "名称", "密材料名",
            "生豆生産国", "Brazil",
        ]))

        #expect(parsed.name == nil)
        #expect(parsed.country == "Brazil")
    }

    /// A photo of a menu lists several coffees; the notes column runs long.
    @Test func notesAreCappedAtOneCardsWorth() {
        let parsed = FieldParser.parse(lines([
            "Notes",
            "Galangal", "Nut Butter", "Clove", "Grape Gummy",
            "White Peach", "Violet", "Jasmine", "Yuzu", "Pear",
        ]))

        #expect(parsed.tastingNotes.count == 6)
    }

    /// OCR garbage has a shape: consonant runs and stray single letters.
    @Test func garbledNotesAreDropped() {
        let parsed = FieldParser.parse(lines(["Flavour:", "stt ler", "USE A AEPTUL"]))
        #expect(parsed.tastingNotes.isEmpty)
    }

    /// Chinese tasting notes are two glyphs, and the roaster's story is long.
    @Test func chineseNotesKeepShortEntriesOnly() {
        let parsed = FieldParser.parse(lines([
            "风味: 白花、柠檬、乌龙茶",
            "世界でも有数のコーヒータウンです",
        ]))

        #expect(parsed.tastingNotes == ["白花", "柠檬", "乌龙茶"])
    }

    /// A lone kana glyph in a Chinese card is an OCR misread, not Japanese.
    @Test func languageDetectionIgnoresStrayKana() {
        let parsed = FieldParser.parse(lines([
            "产地: 厄瓜多尔", "豆种: 改良铁皮卡", "处理: 水洗", "ー",
        ]))

        #expect(parsed.sourceLanguage == "zh")
    }

    @Test func theTallestLineBecomesTheNameAndTheSeedBecomesTheRoaster() {
        let parsed = FieldParser.parse([
            TextExtractor.Line(text: "KLOVER COFFEE PARIS", y: 0.1, x: 0.1, bounds: CGRect(x: 0.1, y: 0.8, width: 0.7, height: 0.05)),
            TextExtractor.Line(text: "Nano Challa", y: 0.3, x: 0.1, bounds: CGRect(x: 0.1, y: 0.55, width: 0.6, height: 0.14)),
            TextExtractor.Line(text: "Washed", y: 0.6, x: 0.1, bounds: CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.04)),
        ])
        #expect(parsed.roaster == "Klover")
        #expect(parsed.name == "Nano Challa")
    }

    @Test func aWeightIsNotTheCoffeeName() {
        let parsed = FieldParser.parse([
            TextExtractor.Line(text: "250g", y: 0.1, x: 0.1, bounds: CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.16)),
            TextExtractor.Line(text: "Nano Challa", y: 0.4, x: 0.1, bounds: CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.08)),
            TextExtractor.Line(text: "Washed", y: 0.7, x: 0.1, bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)),
        ])
        #expect(parsed.name == "Nano Challa")
    }

    @Test func theWordOriginOnALabelIsNotTheRoaster() {
        let parsed = FieldParser.parse(lines([
            "Origin: Ethiopia",
            "Process: Washed",
            "Heirloom",
        ]))
        #expect(parsed.roaster != "Origin")
    }

    @Test func aRoasterLineIsNotUsedAsTheCoffeeName() {
        let parsed = FieldParser.parse([
            TextExtractor.Line(text: "Klover", y: 0.2, x: 0.1, bounds: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.2)),
            TextExtractor.Line(text: "Ethiopia", y: 0.5, x: 0.1, bounds: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.04)),
            TextExtractor.Line(text: "Washed", y: 0.7, x: 0.1, bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.03)),
        ])
        #expect(parsed.roaster == "Klover")
        #expect(parsed.name == nil)
    }

    // MARK: - Vision assist trigger

    @Test func weakParseWantsVisionAssist() {
        var parsed = FieldParser.parse(lines([
            "BLUE BOTTLE COFFEE",
            "THREE AFRICAS",
            "TASTING NOTES",
            "Golden Raisin", "Winey Blueberry", "Lemon Zest",
        ]))
        parsed.linesRead = 6
        #expect(parsed.wantsVisionAssist)
    }

    @Test func threeFieldsWithoutANameOrNotesStillAskForVision() {
        var parsed = FieldParser.parse(lines([
            "Country: Kenya",
            "Region: Nyeri",
            "Process: Washed",
            "Altitude: 1800",
        ]))
        parsed.linesRead = 4
        #expect(parsed.name == nil)
        #expect(parsed.tastingNotes.isEmpty)
        #expect(parsed.filledCount >= 3)
        #expect(parsed.wantsVisionAssist)
    }

    @Test func strongParseSkipsVisionAssist() {
        var parsed = FieldParser.parse(lines([
            "Region : Geera, Jimma",
            "Altitude : 2048 Masl",
            "Variety : Heirloom",
            "Process : Washed",
            "Note : Floral , Citrus , Stonefruits",
        ]))
        parsed.linesRead = 5
        #expect(!parsed.wantsVisionAssist)
    }

    @Test func photoWithoutTextSkipsVisionAssist() {
        var parsed = FieldParser.parse(lines([]))
        parsed.linesRead = 0
        #expect(!parsed.wantsVisionAssist)
    }

    // MARK: - Merging

    @Test func fillMissingNeverOverwrites() {
        var local = ParsedFields()
        local.name = "Local Name"
        local.tastingNotes = ["Yuzu"]

        var vision = ParsedFields()
        vision.name = "Vision Name"
        vision.country = "Kenya"
        vision.tastingNotes = ["Grape"]
        vision.recipe = Brew(dose: 15, water: 225)

        local.fillMissing(from: vision)

        #expect(local.name == "Local Name")
        #expect(local.country == "Kenya")
        #expect(local.tastingNotes == ["Yuzu", "Grape"])
        #expect(local.recipe?.dose == 15)
    }

    @Test func visionCompletesTheNotesWithoutRepeatingOne() {
        var local = ParsedFields()
        local.tastingNotes = ["Peach", "Jasmine"]
        var vision = ParsedFields()
        vision.tastingNotes = ["pêche", "Jasmine", "sun muscat", "Overall Sweet"]
        local.fillMissing(from: vision)
        #expect(local.tastingNotes == ["Peach", "Jasmine", "sun muscat", "Overall Sweet"])
    }

    @Test func notesCutAtTheLimitAskForVision() {
        var parsed = FieldParser.parse(lines([
            "Region : Geera, Jimma",
            "Altitude : 2048 Masl",
            "Variety : Heirloom",
            "Process : Washed",
            "TASTING NOTES",
            "Peach, Jasmine, Lemon",
            "Honey, Raisin, Cocoa",
            "Passion fruit, Overall Sweet",
        ]))
        parsed.linesRead = 8
        #expect(parsed.tastingNotes.count == FieldParser.noteLimit)
        #expect(parsed.wantsVisionAssist)
    }

    // MARK: - Headings over their values

    /// The DR Congo Majirane card of 22 Nov 2026 (Process Coffee). A row of
    /// headings with each value printed under it, in a mono font that reads
    /// 1750 as "175C". Read line by line, PROCESS took "175C" and the notes
    /// came back as "NOTES".
    @Test func headingsOverValuesReadByColumn() {
        func at(_ text: String, _ x: Double, _ y: Double) -> TextExtractor.Line {
            TextExtractor.Line(text: text, y: y, x: x)
        }
        let parsed = FieldParser.parse([
            at("PRO", 0.05, 0.05), at("DR CONGO", 0.25, 0.04), at("MAJIRANE", 0.25, 0.08),
            at("MASL", 0.05, 0.20), at("PRODUCER", 0.30, 0.20), at("PROCESS", 0.70, 0.20),
            at("175C", 0.05, 0.24), at("SMALLHOLDER", 0.30, 0.24), at("WASHED", 0.70, 0.24),
            at("TASTE NOTES", 0.05, 0.36),
            at("PLUM, MOLASSES, LIQUORICE", 0.05, 0.40),
            at("BREW RATING", 0.05, 0.50), at("BREW NOTES", 0.30, 0.50),
            at("BEST BREWED AFTER 21 DAYS", 0.30, 0.54),
        ])

        #expect(parsed.altitude == "1750")
        #expect(parsed.producer == "SMALLHOLDER")
        #expect(parsed.process == "WASHED")
        #expect(parsed.tastingNotes == ["PLUM", "MOLASSES", "LIQUORICE"])
    }

    @Test func aHeadingIsNeverANote() {
        let parsed = FieldParser.parse(lines(["TASTE NOTES", "Plum, Molasses", "BREW RATING", "BREW NOTES"]))
        #expect(parsed.tastingNotes == ["Plum", "Molasses"])
        let inline = FieldParser.parse(lines(["TASTE NOTES: Plum, Molasses"]))
        #expect(inline.tastingNotes == ["Plum", "Molasses"])
    }

    @Test func aNumberIsNotAProcess() {
        var parsed = FieldParser.parse(lines(["Process", "175C", "Altitude", "1O50 masl"]))
        parsed.linesRead = 4
        #expect(parsed.process == nil)
        #expect(parsed.altitude == "1050 masl")
        // A heading whose value was refused asks for a second opinion.
        #expect(parsed.refusedValues == 1)
        #expect(parsed.wantsVisionAssist)
        #expect(FieldParser.parse(lines(["Process: 72h anaerobic"])).process == "72h anaerobic")
    }

    @Test func monoFontDigitsAreRepaired() {
        #expect(FieldParser.repairedDigits("175C") == "1750")
        #expect(FieldParser.repairedDigits("1O50-18OO m") == "1O50-18OO m")
        #expect(FieldParser.repairedDigits("1O50 m") == "1050 m")
        #expect(FieldParser.repairedDigits("Cauca") == "Cauca")
        #expect(FieldParser.repairedDigits("CO2") == "CO2")
    }

    // MARK: - From the scan benchmark of 22 Nov 2026

    /// Glitch Coffee's cards: a cupping grid of headings, then ORIGIN over the
    /// coffee. "Origin" is also a roaster's name, and BALANCE was kept as a note.
    @Test func aCuppingGridAndAnOriginHeadingStayHeadings() {
        let parsed = FieldParser.parse(lines([
            "TASTING NOTES", "WHITE FLOWER, MAYER LEMON, HONEY,", "SMOOTH, ELEGANT",
            "AROMA", "SWEETNESS", "FLAVOR", "MOUTHFEEL", "ACIDITY", "BALANCE", "AFTERTASTE",
            "ORIGIN", "LERIDA", "(LOT.5)", "PANAMA BOQUETE",
        ]))
        #expect(parsed.roaster != "Origin")
        #expect(!parsed.tastingNotes.contains { $0.uppercased() == "BALANCE" })
        #expect(parsed.tastingNotes.first == "WHITE FLOWER")
    }

    /// Black Potion's box: "GESHA WASHED • ECUADOR" under the name, the notes
    /// on the next line.
    @Test func theCoffeesIdentityLineIsNotItsNotes() {
        let parsed = FieldParser.parse(lines([
            "HACIENDA LA PAPAYA", "GESHA WASHED • ECUADOR",
            "LIME • GRAPEFRUIT • DRIED MANGO • GOOSEBERRY • MINT • BROWN SUGAR",
        ]))
        #expect(parsed.tastingNotes == ["LIME", "GRAPEFRUIT", "DRIED MANGO", "GOOSEBERRY", "MINT", "BROWN SUGAR"])
    }
}
