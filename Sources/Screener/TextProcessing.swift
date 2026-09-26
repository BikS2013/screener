import CoreGraphics
import Foundation

/// A recognised text fragment with its bounding box in Vision's normalised, bottom-left-origin space.
struct TextFragment {
    let text: String
    let box: CGRect
}

enum TextLayout {
    /// Rebuilds reading order: fragments whose vertical centres overlap form one line (left → right),
    /// lines are ordered top → bottom and joined with "\n" (or a space when line breaks are not preserved).
    static func assemble(_ fragments: [TextFragment], preserveLineBreaks: Bool) -> String {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        var lines: [[TextFragment]] = []
        for fragment in sorted {
            if let last = lines.last?.last,
               abs(last.box.midY - fragment.box.midY) < 0.5 * min(last.box.height, fragment.box.height) {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }
        let rendered = lines.map { line in
            line.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
        return rendered.joined(separator: preserveLineBreaks ? "\n" : " ")
    }

    /// Normalises Tesseract's plain-text output.
    static func normalizeTesseract(_ raw: String, preserveLineBreaks: Bool) -> String {
        let cleaned = raw.replacingOccurrences(of: "\u{0C}", with: "")
        let lines = cleaned.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if preserveLineBreaks {
            // Keep single blank lines between paragraphs, drop runs of them.
            var out: [String] = []
            for line in lines {
                if line.isEmpty, out.last?.isEmpty ?? true { continue }
                out.append(line)
            }
            while out.last?.isEmpty == true { out.removeLast() }
            return out.joined(separator: "\n")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum GreekText {
    static func isGreek(_ scalar: Unicode.Scalar) -> Bool {
        (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
    }

    static func containsGreek(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isGreek)
    }

    /// Converts polytonic Greek (which Tesseract's model sometimes emits, e.g. "εἶναι")
    /// to modern monotonic spelling ("είναι"). Non-Greek characters are untouched.
    static func toMonotonic(_ text: String) -> String {
        var out = ""
        for character in text {
            let decomposed = String(character).decomposedStringWithCanonicalMapping.unicodeScalars
            guard let base = decomposed.first, isGreek(base) else {
                out.append(character)
                continue
            }
            var scalars = String.UnicodeScalarView()
            var hasAccent = false
            for scalar in decomposed {
                switch scalar.value {
                case 0x0313, 0x0314, 0x0345: // psili, dasia, ypogegrammeni
                    continue
                case 0x0300, 0x0301, 0x0342: // varia, oxia/tonos, perispomeni → tonos
                    if !hasAccent {
                        hasAccent = true
                        scalars.append(Unicode.Scalar(0x0301)!)
                    }
                default:
                    scalars.append(scalar)
                }
            }
            out += String(scalars).precomposedStringWithCanonicalMapping
        }
        return out
    }
}
