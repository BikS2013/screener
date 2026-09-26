import XCTest
@testable import Screener

final class KeyComboTests: XCTestCase {
    func testParsesModifiersAndKey() throws {
        let combo = try KeyCombo.parse("ctrl+option+cmd+t")
        XCTAssertEqual(combo.keyCode, 17)
        XCTAssertEqual(combo.modifiers, [.control, .option, .command])
        XCTAssertEqual(combo.canonical, "ctrl+option+cmd+t")
        XCTAssertEqual(combo.display, "⌃⌥⌘T")
    }

    func testAliasesAndCase() throws {
        XCTAssertEqual(try KeyCombo.parse("Alt+Shift+Command+F5"), try KeyCombo.parse("option+shift+cmd+f5"))
        XCTAssertEqual(try KeyCombo.parse("esc"), try KeyCombo.parse("escape"))
    }

    func testRejectsUnknownTokens() {
        XCTAssertThrowsError(try KeyCombo.parse("hyper+t"))
        XCTAssertThrowsError(try KeyCombo.parse("cmd+nope"))
        XCTAssertThrowsError(try KeyCombo.parse(""))
    }

    func testGlobalSafety() throws {
        XCTAssertFalse(try KeyCombo.parse("t").isSafeGlobalHotkey)
        XCTAssertFalse(try KeyCombo.parse("shift+t").isSafeGlobalHotkey)
        XCTAssertFalse(try KeyCombo.parse("f").isSafeGlobalHotkey)
        XCTAssertTrue(try KeyCombo.parse("f13").isSafeGlobalHotkey)
        XCTAssertTrue(try KeyCombo.parse("cmd+shift+2").isSafeGlobalHotkey)
    }
}

final class TextLayoutTests: XCTestCase {
    /// A word at character column `column` of row `row` (10 px per character, 20 px rows, 30 px pitch).
    private func word(_ text: String, column: Int, row: CGFloat) -> LayoutWord {
        LayoutWord(text: text, box: CGRect(x: CGFloat(column) * 10, y: row * 30, width: CGFloat(text.count) * 10, height: 20))
    }

    func testRowsMergeFragmentsOnTheSameLineAndOrderTopToBottom() {
        let rows = TextLayout.rows(from: [
            [word("second", column: 0, row: 1)],
            [word("world", column: 6, row: 0)],
            [word("Hello", column: 0, row: 0)],
        ])
        XCTAssertEqual(rows.map { $0.words.map(\.text) }, [["Hello", "world"], ["second"]])
    }

    func testPreservedKeepsColumnsIndentationAndParagraphGaps() {
        let rows = TextLayout.rows(from: [
            [word("Name", column: 0, row: 0), word("Qty", column: 20, row: 0)],
            [word("Tea", column: 0, row: 1), word("45", column: 20, row: 1)],
            [word("next", column: 4, row: 3), word("paragraph", column: 9, row: 3)],
        ])
        XCTAssertEqual(TextLayout.render(rows, format: .preserved),
                       "Name                Qty\nTea                 45\n\n    next paragraph")
    }

    func testPlainJoinsLinesAndRemovesLineEndHyphenation() {
        let rows = TextLayout.rows(from: [
            [word("continues", column: 0, row: 0), word("on", column: 10, row: 0), word("the", column: 13, row: 0), word("li-", column: 17, row: 0)],
            [word("ne", column: 0, row: 1), word("here.", column: 3, row: 1)],
            [word("Well-known", column: 0, row: 2), word("-", column: 11, row: 2)],
            [word("Next", column: 0, row: 3)],
        ])
        XCTAssertEqual(TextLayout.render(rows, format: .plain), "continues on the line here. Well-known - Next")
    }

    func testTesseractTSVParsing() {
        let tsv = """
        level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
        1\t1\t0\t0\t0\t0\t0\t0\t500\t100\t-1\t
        5\t1\t1\t1\t1\t1\t10\t5\t40\t20\t96\tΚαλημέρα
        5\t1\t1\t1\t1\t2\t60\t5\t40\t20\t95\tκόσμε
        5\t1\t1\t1\t2\t1\t10\t40\t40\t20\t93\tHello
        5\t1\t1\t1\t2\t2\t60\t40\t40\t20\t-1\t\u{20}
        """
        let lines = TextLayout.parseTesseractTSV(tsv)
        XCTAssertEqual(lines.map { $0.map(\.text) }, [["Καλημέρα", "κόσμε"], ["Hello"]])
        XCTAssertEqual(lines[0][1].box, CGRect(x: 60, y: 5, width: 40, height: 20))
    }
}

final class GreekTextTests: XCTestCase {
    func testDetection() {
        XCTAssertTrue(GreekText.containsGreek("abc Καλημέρα"))
        XCTAssertTrue(GreekText.containsGreek("εἶναι"))
        XCTAssertFalse(GreekText.containsGreek("Hello, café"))
    }

    func testMonotonic() {
        XCTAssertEqual(GreekText.toMonotonic("εἶναι"), "είναι")
        XCTAssertEqual(GreekText.toMonotonic("ἡ ὁδὸς ᾠδῇ"), "η οδός ωδή")
        XCTAssertEqual(GreekText.toMonotonic("Καλημέρα café"), "Καλημέρα café")
    }
}

final class ConfigTests: XCTestCase {
    private func exampleData() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("config.example.json"))
    }

    func testExampleDecodes() throws {
        let config = try ConfigStore.decode(exampleData())
        XCTAssertEqual(config.ocr.engine, .auto)
        XCTAssertEqual(config.hotkeys.cancel, "escape")
    }

    func testMissingKeyIsReportedWithPath() throws {
        var json = try JSONSerialization.jsonObject(with: exampleData()) as! [String: Any]
        var ocr = json["ocr"] as! [String: Any]
        ocr.removeValue(forKey: "engine")
        json["ocr"] = ocr
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try ConfigStore.decode(data)) { error in
            XCTAssertEqual(error as? ConfigError, .invalid("missing required key 'ocr.engine'."))
        }
    }

    func testValidationRejectsUnsafeGlobalHotkey() throws {
        var config = try ConfigStore.decode(exampleData())
        config.ocr.engine = .vision
        config.hotkeys.activate = "t"
        XCTAssertThrowsError(try ConfigStore.validate(config))
    }

    func testValidationRejectsOutOfRangeValues() throws {
        var config = try ConfigStore.decode(exampleData())
        config.ocr.engine = .vision
        XCTAssertNoThrow(try ConfigStore.validate(config))
        config.overlay.dimOpacity = 1.5
        XCTAssertThrowsError(try ConfigStore.validate(config))
    }
}

@MainActor
final class GreekCorrectorTests: XCTestCase {
    private var corrector: GreekCorrector!

    override func setUp() async throws {
        let hasGreek = await MainActor.run { NSSpellChecker.shared.availableLanguages.contains { $0.hasPrefix("el") } }
        try XCTSkipUnless(hasGreek, "Greek spelling dictionary not installed")
        corrector = GreekCorrector(spell: SystemSpellChecker())
    }

    func testMicroSignBecomesMu() {
        XCTAssertEqual(corrector.correct("Το κείµενο έχει µια λέξη"), "Το κείμενο έχει μια λέξη")
    }

    func testLatinWordsInGreekContext() {
        XCTAssertEqual(corrector.correct("αυτό είναι Eva τεστ"), "αυτό είναι ένα τεστ")
        XCTAssertEqual(corrector.correct("ένα Άνθρωπο kat ΟΝΟΜΑ."), "ένα Άνθρωπο και ΟΝΟΜΑ.")
    }

    func testGenuineLatinWordsAreKept() {
        let text = "Η εταιρεία IBM και η ΕΤΕ, OK; ένα iPhone από την Apple και email info@nbg.gr"
        XCTAssertEqual(corrector.correct(text), text)
        XCTAssertEqual(corrector.correct("Hello world, this is a test."), "Hello world, this is a test.")
    }

    func testMixedScriptWord() {
        XCTAssertEqual(corrector.correct("στην Αθnνα σήμερα"), "στην Αθήνα σήμερα")
    }

    func testAccentRepair() {
        XCTAssertEqual(corrector.correct("αυτό είναι ενα τεστ"), "αυτό είναι ένα τεστ")
        XCTAssertEqual(corrector.correct("Ό Κώστας έχει"), "Ο Κώστας έχει")
        XCTAssertEqual(corrector.correct("Η ΕΘΝΙΚΗ ΤΡΑΠΕΖΑ"), "Η ΕΘΝΙΚΗ ΤΡΑΠΕΖΑ")
    }

    func testDigits() {
        XCTAssertEqual(corrector.correct("ο κωδικός είναι ΑΒΓ-Ί23"), "ο κωδικός είναι ΑΒΓ-123")
        XCTAssertEqual(corrector.correct("το 2O26 και το I2C"), "το 2026 και το I2C")
    }

    func testWhitespaceAndLinesPreserved() {
        XCTAssertEqual(corrector.correct("µια  λέξη\n\nδεύτερη\tγραμμή"), "μια  λέξη\n\nδεύτερη\tγραμμή")
    }
}

final class LineNavigatorTests: XCTestCase {
    // Two columns, three rows each (AppKit coordinates: larger y is higher on screen).
    private let rects = [
        CGRect(x: 0, y: 300, width: 200, height: 20), CGRect(x: 300, y: 300, width: 200, height: 20),
        CGRect(x: 0, y: 260, width: 200, height: 20), CGRect(x: 300, y: 260, width: 200, height: 20),
        CGRect(x: 0, y: 220, width: 200, height: 20), CGRect(x: 300, y: 220, width: 200, height: 20),
    ]

    func testReadingOrder() {
        let shuffled = [rects[5], rects[0], rects[3], rects[2], rects[4], rects[1]]
        XCTAssertEqual(LineNavigator.readingOrder(shuffled), rects)
    }

    func testVerticalMovesStayInColumn() {
        XCTAssertEqual(LineNavigator.neighbour(of: 1, in: rects, direction: .down), 3)
        XCTAssertEqual(LineNavigator.neighbour(of: 3, in: rects, direction: .up), 1)
        XCTAssertNil(LineNavigator.neighbour(of: 4, in: rects, direction: .down))
    }

    func testHorizontalMovesStayInRow() {
        XCTAssertEqual(LineNavigator.neighbour(of: 2, in: rects, direction: .right), 3)
        XCTAssertEqual(LineNavigator.neighbour(of: 3, in: rects, direction: .left), 2)
        XCTAssertNil(LineNavigator.neighbour(of: 3, in: rects, direction: .right))
    }

    func testNearest() {
        XCTAssertEqual(LineNavigator.nearest(to: CGPoint(x: 350, y: 225), in: rects), 5)
    }
}

final class KeyboardConfigTests: XCTestCase {
    private func example() throws -> AppConfig {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var config = try ConfigStore.decode(Data(contentsOf: root.appendingPathComponent("config.example.json")))
        config.ocr.engine = .vision
        return config
    }

    func testExampleIsValidAndBindingsResolve() throws {
        let config = try example()
        XCTAssertNoThrow(try ConfigStore.validate(config))
        let bindings = try KeyboardBindings(config: config)
        XCTAssertEqual(bindings.fasterModifier, .shift)
        XCTAssertEqual(bindings.toggleFormat.canonical, "f")
        XCTAssertEqual(bindings.startFormat, .preserved)
        XCTAssertEqual(bindings.arrowsDisplay, "↑↓←→")
    }

    func testThreeSpeedLevels() throws {
        let bindings = try KeyboardBindings(config: try example())
        XCTAssertEqual(bindings.step(for: []), 20)          // default = the former "fast" step
        XCTAssertEqual(bindings.step(for: .shift), 100)     // new, even faster
        XCTAssertEqual(bindings.step(for: .option), 2)      // former default, now fine
        XCTAssertNil(bindings.step(for: [.shift, .option]))
        XCTAssertNil(bindings.step(for: .command))
    }

    func testDuplicateKeysRejected() throws {
        var config = try example()
        config.keyboard.anchor = "return"
        XCTAssertThrowsError(try ConfigStore.validate(config))
        config = try example()
        config.keyboard.toggleTextMode = "escape"
        XCTAssertThrowsError(try ConfigStore.validate(config))
        config = try example()
        config.keyboard.toggleFormat = "t"  // same as toggleTextMode
        XCTAssertThrowsError(try ConfigStore.validate(config))
    }

    func testMoveKeysMustBePlain() throws {
        var config = try example()
        config.keyboard.moveUp = "shift+up"
        XCTAssertThrowsError(try ConfigStore.validate(config))
    }

    func testStepsAndModifiersValidated() throws {
        var config = try example()
        config.keyboard.fasterStepPoints = 10  // must exceed the default step
        XCTAssertThrowsError(try ConfigStore.validate(config))
        config = try example()
        config.keyboard.defaultStepPoints = 1  // must exceed the fine step
        XCTAssertThrowsError(try ConfigStore.validate(config))
        config = try example()
        config.keyboard.fineModifier = "shift"  // same as fasterModifier
        XCTAssertThrowsError(try ConfigStore.validate(config))
        config = try example()
        config.keyboard.extendModifier = "hyper"
        XCTAssertThrowsError(try ConfigStore.validate(config))
    }
}

final class BundledTessdataTests: XCTestCase {
    func testCopiesModelsWithoutOverwriting() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundled = root.appendingPathComponent("bundle"), target = root.appendingPathComponent("tessdata")
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("new-ell".utf8).write(to: bundled.appendingPathComponent("ell.traineddata"))
        try Data("new-eng".utf8).write(to: bundled.appendingPathComponent("eng.traineddata"))
        try Data("notes".utf8).write(to: bundled.appendingPathComponent("README.txt"))
        try Data("user-eng".utf8).write(to: target.appendingPathComponent("eng.traineddata"))

        try ConfigStore.installBundledTessdata(from: bundled, into: target)

        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("ell.traineddata"), encoding: .utf8), "new-ell")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("eng.traineddata"), encoding: .utf8), "user-eng")
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("README.txt").path))
    }
}
