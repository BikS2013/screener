import AppKit
import Foundation
import Vision

// Every key is required. A missing or invalid key raises a ConfigError; no defaults are ever substituted.

enum OCREngine: String, Codable, CaseIterable {
    case auto, vision, tesseract
}

struct HotkeysConfig: Codable, Equatable {
    var activate: String
    var cancel: String
    var showHistory: String
}

struct OCRConfig: Codable, Equatable {
    var engine: OCREngine
    var visionLanguages: [String]
    var tesseractLanguages: String
    var tesseractPath: String
    var tessdataDir: String
    var tesseractPageSegMode: Int
    var languageCorrection: Bool
}

struct OutputConfig: Codable, Equatable {
    var preserveLineBreaks: Bool
    var greekMonotonic: Bool
    var greekCorrection: Bool
}

struct KeyboardConfig: Codable, Equatable {
    var moveUp: String
    var moveDown: String
    var moveLeft: String
    var moveRight: String
    var defaultStepPoints: Double
    var fineModifier: String
    var fineStepPoints: Double
    var fasterModifier: String
    var fasterStepPoints: Double
    var extendModifier: String
    var anchor: String
    var confirm: String
    var nextScreen: String
    var toggleTextMode: String
    var startInTextMode: Bool
}

struct FeedbackConfig: Codable, Equatable {
    var toast: Bool
    var toastDurationSeconds: Double
    var sound: Bool
    var soundName: String
}

struct HistoryConfig: Codable, Equatable {
    var size: Int
}

struct OverlayConfig: Codable, Equatable {
    var dimOpacity: Double
}

struct AppConfig: Codable, Equatable {
    var hotkeys: HotkeysConfig
    var keyboard: KeyboardConfig
    var ocr: OCRConfig
    var output: OutputConfig
    var feedback: FeedbackConfig
    var history: HistoryConfig
    var overlay: OverlayConfig
}

enum ConfigError: LocalizedError, Equatable {
    case missingFile(String)
    case unreadable(String, String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "Configuration file not found at \(path). Create it (menu → Create Config from Example) or copy config.example.json there."
        case .unreadable(let path, let reason):
            return "Configuration file \(path) could not be read: \(reason)"
        case .invalid(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}

enum ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tool-agents/screener", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("config.json")

    static func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
    }

    static func load(from url: URL = fileURL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.missingFile(url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(url.path, error.localizedDescription)
        }
        let config = try decode(data)
        try validate(config)
        return config
    }

    static func decode(_ data: Data) throws -> AppConfig {
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalid(describe(error))
        }
    }

    static func save(_ config: AppConfig, to url: URL = fileURL) throws {
        try validate(config)
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Copies the bundled example into place. Only ever runs on an explicit user action.
    static func createFromExample(_ exampleURL: URL) throws {
        try ensureDirectory()
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConfigError.invalid("\(fileURL.path) already exists; refusing to overwrite it.")
        }
        try FileManager.default.copyItem(at: exampleURL, to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Copies the Tesseract models shipped inside the app into ~/.tool-agents/screener/tessdata.
    /// Existing files are kept. Only ever runs on an explicit user action (together with createFromExample).
    static func installBundledTessdata(from bundled: URL, into destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(atPath: bundled.path) where file.hasSuffix(".traineddata") {
            let target = destination.appendingPathComponent(file)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try fm.copyItem(at: bundled.appendingPathComponent(file), to: target)
        }
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    // MARK: - Validation

    static func validate(_ c: AppConfig) throws {
        let combos: [(String, KeyCombo)] = try [
            ("hotkeys.activate", parseHotkey(c.hotkeys.activate, key: "hotkeys.activate")),
            ("hotkeys.cancel", parseHotkey(c.hotkeys.cancel, key: "hotkeys.cancel")),
            ("hotkeys.showHistory", parseHotkey(c.hotkeys.showHistory, key: "hotkeys.showHistory")),
        ]
        for (name, combo) in combos where name != "hotkeys.cancel" && !combo.isSafeGlobalHotkey {
            throw ConfigError.invalid("\(name) '\(combo.canonical)' needs at least one of cmd/ctrl/option (or must be a function key).")
        }
        if combos[0].1 == combos[2].1 {
            throw ConfigError.invalid("hotkeys.activate and hotkeys.showHistory must differ.")
        }

        try validateKeyboard(c.keyboard, cancel: combos[1].1)

        if c.ocr.engine != .tesseract {
            guard !c.ocr.visionLanguages.isEmpty else {
                throw ConfigError.invalid("ocr.visionLanguages must list at least one language.")
            }
            let supported = Set((try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? [])
            for lang in c.ocr.visionLanguages where !supported.contains(lang) {
                throw ConfigError.invalid("ocr.visionLanguages: '\(lang)' is not supported by Apple Vision on this Mac.")
            }
        }
        if c.ocr.engine != .vision {
            let exe = expandTilde(c.ocr.tesseractPath)
            guard FileManager.default.isExecutableFile(atPath: exe) else {
                throw ConfigError.invalid("ocr.tesseractPath '\(exe)' is not an executable file (brew install tesseract).")
            }
            let langs = c.ocr.tesseractLanguages.split(separator: "+").map(String.init)
            guard !langs.isEmpty, langs.allSatisfy({ !$0.isEmpty }) else {
                throw ConfigError.invalid("ocr.tesseractLanguages must look like 'ell+eng'.")
            }
            let dir = expandTilde(c.ocr.tessdataDir)
            for lang in langs {
                let file = (dir as NSString).appendingPathComponent("\(lang).traineddata")
                guard FileManager.default.fileExists(atPath: file) else {
                    throw ConfigError.invalid("ocr.tessdataDir: missing \(file) (run scripts/install-tessdata.sh).")
                }
            }
            guard (0...13).contains(c.ocr.tesseractPageSegMode) else {
                throw ConfigError.invalid("ocr.tesseractPageSegMode must be between 0 and 13.")
            }
        }
        if c.output.greekCorrection, c.ocr.engine != .vision,
           !NSSpellChecker.shared.availableLanguages.contains(where: { $0.hasPrefix("el") }) {
            throw ConfigError.invalid("output.greekCorrection needs the Greek spelling dictionary (System Settings → Keyboard → Text Input → Spelling), or set it to false.")
        }
        guard c.feedback.toastDurationSeconds > 0, c.feedback.toastDurationSeconds <= 30 else {
            throw ConfigError.invalid("feedback.toastDurationSeconds must be > 0 and <= 30.")
        }
        guard NSSound(named: NSSound.Name(c.feedback.soundName)) != nil else {
            throw ConfigError.invalid("feedback.soundName '\(c.feedback.soundName)' is not a system sound (see /System/Library/Sounds).")
        }
        guard (1...500).contains(c.history.size) else {
            throw ConfigError.invalid("history.size must be between 1 and 500.")
        }
        guard (0.0...0.9).contains(c.overlay.dimOpacity) else {
            throw ConfigError.invalid("overlay.dimOpacity must be between 0.0 and 0.9.")
        }
    }

    private static func validateKeyboard(_ k: KeyboardConfig, cancel: KeyCombo) throws {
        let moves = try [
            ("keyboard.moveUp", k.moveUp), ("keyboard.moveDown", k.moveDown),
            ("keyboard.moveLeft", k.moveLeft), ("keyboard.moveRight", k.moveRight),
        ].map { name, value -> (String, KeyCombo) in
            let combo = try parseHotkey(value, key: name)
            guard combo.modifiers.isEmpty else {
                throw ConfigError.invalid("\(name) must be a plain key without modifiers (the modifiers come from keyboard.fasterModifier, keyboard.fineModifier and keyboard.extendModifier).")
            }
            return (name, combo)
        }
        let actions = try [
            ("keyboard.anchor", k.anchor), ("keyboard.confirm", k.confirm),
            ("keyboard.nextScreen", k.nextScreen), ("keyboard.toggleTextMode", k.toggleTextMode),
        ].map { name, value in (name, try parseHotkey(value, key: name)) }
        let all = moves + actions + [("hotkeys.cancel", cancel)]
        for (i, first) in all.enumerated() {
            for second in all[(i + 1)...] where first.1 == second.1 {
                throw ConfigError.invalid("\(first.0) and \(second.0) use the same key '\(first.1.canonical)'.")
            }
        }
        var modifiers: [String: NSEvent.ModifierFlags] = [:]
        for (name, value) in [("keyboard.fineModifier", k.fineModifier), ("keyboard.fasterModifier", k.fasterModifier),
                              ("keyboard.extendModifier", k.extendModifier)] {
            do {
                modifiers[name] = try KeyCombo.parseModifier(value)
            } catch {
                throw ConfigError.invalid("\(name): \(error.localizedDescription)")
            }
        }
        guard modifiers["keyboard.fineModifier"] != modifiers["keyboard.fasterModifier"] else {
            throw ConfigError.invalid("keyboard.fineModifier and keyboard.fasterModifier must differ.")
        }
        guard k.fineStepPoints > 0 else {
            throw ConfigError.invalid("keyboard.fineStepPoints must be > 0.")
        }
        guard k.defaultStepPoints > k.fineStepPoints else {
            throw ConfigError.invalid("keyboard.defaultStepPoints must be greater than keyboard.fineStepPoints.")
        }
        guard k.fasterStepPoints > k.defaultStepPoints, k.fasterStepPoints <= 2000 else {
            throw ConfigError.invalid("keyboard.fasterStepPoints must be greater than keyboard.defaultStepPoints and <= 2000.")
        }
    }

    private static func parseHotkey(_ value: String, key: String) throws -> KeyCombo {
        do {
            return try KeyCombo.parse(value)
        } catch {
            throw ConfigError.invalid("\(key): \(error.localizedDescription)")
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ ctx: DecodingError.Context, _ extra: CodingKey? = nil) -> String {
            let keys = ctx.codingPath + (extra.map { [$0] } ?? [])
            return keys.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let ctx):
            return "missing required key '\(path(ctx, key))'."
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "wrong type or null value at '\(path(ctx))' (\(ctx.debugDescription))."
        case .dataCorrupted(let ctx):
            let where_ = path(ctx)
            return where_.isEmpty ? "malformed JSON (\(ctx.debugDescription))." : "invalid value at '\(where_)' (\(ctx.debugDescription))."
        @unknown default:
            return error.localizedDescription
        }
    }
}
