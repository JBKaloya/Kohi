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
        #expect(local.tastingNotes == ["Yuzu"])
        #expect(local.recipe?.dose == 15)
    }
}
