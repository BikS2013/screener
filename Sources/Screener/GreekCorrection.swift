import AppKit
import Foundation

/// Spell-checking seam so the corrector can be tested without the system dictionaries.
@MainActor
protocol SpellChecking {
    func isValid(_ word: String, language: String) -> Bool
    func guesses(_ word: String, language: String) -> [String]
}

/// NSSpellChecker is not thread-safe: use it from the main actor only.
@MainActor
struct SystemSpellChecker: SpellChecking {
    private let checker = NSSpellChecker.shared

    func isValid(_ word: String, language: String) -> Bool {
        checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                              inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    func guesses(_ word: String, language: String) -> [String] {
        checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                        language: language, inSpellDocumentWithTag: 0) ?? []
    }
}

/// Repairs the typical Tesseract mistakes on Greek text:
///  - look-alike symbols (µ MICRO SIGN → μ) and Latin letters inside Greek words ("κείµενο", "Αθnνα");
///  - whole words read in the wrong script inside Greek sentences ("Eva" → "ένα", "kat" → "και"),
///    while real Latin words ("IBM", "OK", "iPhone") are kept;
///  - missing or spurious accents ("ενα" → "ένα", "Ό" → "Ο");
///  - letters read instead of digits ("ΑΒΓ-Ί23" → "ΑΒΓ-123").
/// Every replacement of a whole word is confirmed by the Greek spell checker.
@MainActor
struct GreekCorrector {
    let spell: SpellChecking

    static let latinToGreek: [Character: [Character]] = [
        "A": ["Α"], "B": ["Β"], "E": ["Ε"], "H": ["Η"], "I": ["Ι"], "K": ["Κ"], "M": ["Μ"], "N": ["Ν"],
        "O": ["Ο"], "P": ["Ρ"], "T": ["Τ"], "X": ["Χ"], "Y": ["Υ"], "Z": ["Ζ"],
        "a": ["α"], "o": ["ο"], "v": ["ν"], "u": ["υ"], "i": ["ι"], "k": ["κ"], "x": ["χ"], "p": ["ρ"],
        "n": ["η", "π"], "t": ["τ", "ι"], "e": ["ε"], "y": ["γ", "υ"], "w": ["ω"],
        "\u{00B5}": ["μ"],
    ]

    static let greekToLatin: [Character: Character] = [
        "Α": "A", "Β": "B", "Ε": "E", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P",
        "Τ": "T", "Χ": "X", "Υ": "Y", "Ζ": "Z", "α": "a", "ο": "o", "ν": "v", "υ": "u", "ι": "i", "κ": "k",
        "χ": "x", "ρ": "p", "τ": "t", "ε": "e", "γ": "y", "ω": "w",
    ]

    private static let oneLookalikes: Set<Character> = ["Ί", "Ι", "I", "l", "|", "ι", "ί", "ї"]
    private static let zeroLookalikes: Set<Character> = ["Ο", "O", "ο", "o", "Ό", "ό"]
    private static let maxCandidates = 64

    func correct(_ text: String) -> String {
        text.components(separatedBy: "\n").map(correctLine).joined(separator: "\n")
    }

    // MARK: - Line / token handling

    private struct Token {
        var leading: String
        var core: String
        var trailing: String
        var text: String { leading + core + trailing }
    }

    private func correctLine(_ line: String) -> String {
        // Split on spaces while keeping the exact whitespace so layout survives.
        var pieces: [(word: String, separator: String)] = []
        var word = "", separator = ""
        for character in line {
            if character == " " || character == "\t" {
                separator.append(character)
            } else {
                if !separator.isEmpty {
                    pieces.append((word, separator))
                    word = ""
                    separator = ""
                }
                word.append(character)
            }
        }
        pieces.append((word, separator))

        var tokens = pieces.map { Self.split($0.word) }
        let scripts = tokens.map { Self.script(of: $0.core) }
        for index in tokens.indices where !tokens[index].core.isEmpty {
            let context = greekContext(at: index, scripts: scripts)
            let sentenceStart = index == 0 || tokens[index - 1].trailing.last.map { ".!;?:·".contains($0) } ?? false
            tokens[index].core = correctWord(tokens[index].core, greekContext: context, sentenceStart: sentenceStart)
        }
        return zip(tokens, pieces).map { $0.text + $1.separator }.joined()
    }

    private static func split(_ word: String) -> Token {
        let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = word.firstIndex(where: isCore), let last = word.lastIndex(where: isCore) else {
            return Token(leading: word, core: "", trailing: "")
        }
        return Token(leading: String(word[..<first]), core: String(word[first...last]),
                     trailing: String(word[word.index(after: last)...]))
    }

    private enum Script { case greek, latin, mixed, other }

    private static func script(of core: String) -> Script {
        var greek = 0, latin = 0
        for scalar in core.unicodeScalars {
            if GreekText.isGreek(scalar) { greek += 1 } else if isLatinLetter(scalar) { latin += 1 }
        }
        switch (greek > 0, latin > 0) {
        case (true, true): return .mixed
        case (true, false): return .greek
        case (false, true): return .latin
        default: return .other
        }
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    /// A word sits in Greek context when a neighbouring word is Greek and Greek words dominate the line.
    private func greekContext(at index: Int, scripts: [Script]) -> Bool {
        let others = scripts.enumerated().filter { $0.offset != index && $0.element != .other }
        let greek = others.filter { $0.element == .greek || $0.element == .mixed }.count
        guard greek * 2 > others.count else { return false }
        func neighbour(_ step: Int) -> Script? {
            var i = index + step
            while scripts.indices.contains(i) {
                if scripts[i] != .other { return scripts[i] }
                i += step
            }
            return nil
        }
        return [neighbour(-1), neighbour(1)].contains { $0 == .greek || $0 == .mixed }
    }

    // MARK: - Word correction

    func correctWord(_ core: String, greekContext: Bool, sentenceStart: Bool) -> String {
        var word = fixDigits(core)
        let greekCount = word.unicodeScalars.filter(GreekText.isGreek).count
        let latinCount = word.unicodeScalars.filter(Self.isLatinLetter).count
        let hasMicro = word.contains("\u{00B5}")

        if greekCount > 0, latinCount > 0 || hasMicro {
            if greekCount >= latinCount {
                word = toGreek(word) ?? deterministicGreek(word)
            } else {
                word = String(word.map { Self.greekToLatin[$0] ?? $0 })
            }
        } else if greekCount == 0, latinCount > 0, greekContext, isFullyMappable(word),
                  !isGenuineLatin(word), let greek = toGreek(word) {
            // Tesseract often reads a lowercase "έ" as a capital "E": inside a sentence a converted
            // Capitalised word ("Eva") is really lowercase ("ένα").
            let letters = word.filter(\.isLetter)
            let capitalised = letters.count > 1 && letters.first!.isUppercase && letters.dropFirst().allSatisfy(\.isLowercase)
            if capitalised, !sentenceStart {
                word = repairAccents(greek.prefix(1).lowercased() + greek.dropFirst())
            } else {
                word = greek
            }
        }

        if word.unicodeScalars.contains(where: GreekText.isGreek),
           !word.unicodeScalars.contains(where: Self.isLatinLetter) {
            word = repairAccents(word)
        }
        return word
    }

    /// Latin words kept as-is: all-caps words that are valid English in lower case ("OK"), or
    /// words with letters that have no Greek look-alike (checked by isFullyMappable).
    private func isGenuineLatin(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        let allCaps = !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        return allCaps && letters.count > 1 && spell.isValid(word.lowercased(), language: "en")
    }

    private func isFullyMappable(_ word: String) -> Bool {
        word.allSatisfy { !$0.isLetter || Self.latinToGreek[$0] != nil || $0.unicodeScalars.allSatisfy(GreekText.isGreek) }
    }

    /// Tries every look-alike combination and returns the first spelling the Greek dictionary accepts
    /// (directly or after restoring accents).
    private func toGreek(_ word: String) -> String? {
        let candidates = greekCandidates(word)
        if let valid = candidates.first(where: { spell.isValid($0, language: "el") }) { return valid }
        for candidate in candidates {
            let repaired = repairAccents(candidate)
            if repaired != candidate { return repaired }
        }
        return nil
    }

    private func greekCandidates(_ word: String) -> [String] {
        var results = [""]
        for character in word {
            let options = Self.latinToGreek[character] ?? [character]
            results = results.flatMap { prefix in options.map { prefix + String($0) } }
            if results.count > Self.maxCandidates { results = Array(results.prefix(Self.maxCandidates)) }
        }
        return results
    }

    private func deterministicGreek(_ word: String) -> String {
        String(word.map { Self.latinToGreek[$0]?.first ?? $0 })
    }

    /// Fixes accents on a Greek word the dictionary rejects, using a suggestion that differs only in diacritics.
    /// All-caps words are left alone: Greek capitals are written without accents.
    func repairAccents(_ word: String) -> String {
        let letters = word.filter(\.isLetter)
        guard !letters.isEmpty else { return word }
        if letters.count > 1, letters.allSatisfy(\.isUppercase) { return word }
        if spell.isValid(word, language: "el") { return word }

        let base = Self.baseForm(word)
        let stripped = Self.stripAccents(word)
        var suggestions = spell.guesses(word, language: "el")
        if stripped != word { suggestions.insert(stripped, at: 0) }
        for suggestion in suggestions where Self.baseForm(suggestion) == base {
            if suggestion == stripped, !spell.isValid(stripped, language: "el") { continue }
            return Self.transferCase(from: word, to: suggestion)
        }
        return word
    }

    static func stripAccents(_ word: String) -> String {
        String(String.UnicodeScalarView(word.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !(0x0300...0x036F).contains($0.value)
        })).precomposedStringWithCanonicalMapping
    }

    private static func baseForm(_ word: String) -> String {
        stripAccents(word).lowercased().replacingOccurrences(of: "ς", with: "σ")
    }

    /// Keeps the capitalisation of the OCR'd word while taking the accents from the suggestion.
    private static func transferCase(from original: String, to suggestion: String) -> String {
        guard original.count == suggestion.count else { return suggestion }
        return String(zip(original, suggestion).map { source, target -> String in
            source.isUppercase ? String(target).uppercased() : String(target).lowercased()
        }.joined())
    }

    // MARK: - Digits

    /// A lone letter that looks like 1 or 0 and touches a digit becomes that digit ("Ί23" → "123", "2O26" → "2026").
    private func fixDigits(_ word: String) -> String {
        guard word.contains(where: \.isNumber) else { return word }
        var characters = Array(word)
        for i in characters.indices {
            let previous = i > 0 ? characters[i - 1] : nil
            let next = i + 1 < characters.count ? characters[i + 1] : nil
            let prevLetter = previous?.isLetter ?? false
            let nextLetter = next?.isLetter ?? false
            guard !prevLetter, !nextLetter else { continue }
            let digitsBefore = characters[..<i].reversed().prefix { $0.isNumber }.count
            let digitsAfter = characters[(i + 1)...].prefix { $0.isNumber }.count
            // At least two neighbouring digits, so identifiers like "I2C" stay intact.
            guard digitsBefore + digitsAfter >= 2 else { continue }
            if Self.oneLookalikes.contains(characters[i]) {
                characters[i] = "1"
            } else if Self.zeroLookalikes.contains(characters[i]), digitsBefore > 0, digitsAfter > 0 {
                characters[i] = "0"
            }
        }
        return String(characters)
    }
}
