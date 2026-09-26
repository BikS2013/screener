import CoreGraphics
import Foundation

/// How recognised text is laid out in the clipboard.
enum TextFormat: String {
    /// Keeps the on-screen layout: line breaks, indentation, column alignment and paragraph gaps.
    case preserved
    /// One sequential text: lines joined, line-end hyphenation removed, spacing collapsed.
    case plain
}

/// A recognised word (or phrase) with its box in image coordinates (top-left origin, y grows downwards).
struct LayoutWord: Equatable {
    let text: String
    let box: CGRect
}

/// One visual row of text, words ordered left to right.
struct LayoutLine {
    var words: [LayoutWord]
    var box: CGRect { words.dropFirst().reduce(words[0].box) { $0.union($1.box) } }
}

enum TextLayout {
    /// Merges fragments (Vision observations or Tesseract lines) whose vertical centres overlap into rows,
    /// so columns of one visual row end up on one line. Rows are ordered top to bottom.
    static func rows(from fragments: [[LayoutWord]]) -> [LayoutLine] {
        let lines = fragments
            .map { $0.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
            .filter { !$0.isEmpty }
            .map { LayoutLine(words: $0) }
            .sorted { $0.box.midY < $1.box.midY }
        var rows: [LayoutLine] = []
        for line in lines {
            if let last = rows.last,
               abs(last.box.midY - line.box.midY) < 0.5 * min(last.box.height, line.box.height) {
                rows[rows.count - 1].words += line.words
            } else {
                rows.append(line)
            }
        }
        return rows.map { LayoutLine(words: $0.words.sorted { $0.box.minX < $1.box.minX }) }
    }

    static func render(_ rows: [LayoutLine], format: TextFormat) -> String {
        switch format {
        case .preserved: return renderPreserved(rows)
        case .plain: return renderPlain(rows)
        }
    }

    /// Places words on a character grid derived from the median character width, so indentation and
    /// column alignment survive; a vertical gap taller than a line becomes a blank line. Words at ordinary
    /// word spacing get a single space: only real column gaps are aligned to the grid.
    static func renderPreserved(_ rows: [LayoutLine]) -> String {
        let words = rows.flatMap(\.words)
        guard !words.isEmpty else { return "" }
        let charWidth = max(median(words.map { $0.box.width / CGFloat(max($0.text.count, 1)) }), 1)
        let lineHeight = median(rows.map(\.box.height))
        let left = words.map(\.box.minX).min() ?? 0

        var output: [String] = []
        var previousBottom: CGFloat?
        for row in rows {
            if let previousBottom, row.box.minY - previousBottom > 0.8 * lineHeight {
                output.append("")
            }
            var line = ""
            var previousRight: CGFloat?
            for word in row.words {
                let column = Int(((word.box.minX - left) / charWidth).rounded())
                let padding: Int
                if let previousRight {
                    let isColumnGap = word.box.minX - previousRight > columnGapInChars * charWidth
                    padding = isColumnGap ? max(2, column - line.count) : 1
                } else {
                    padding = column
                }
                line += String(repeating: " ", count: max(padding, 0)) + word.text
                previousRight = word.box.maxX
            }
            output.append(line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
            previousBottom = row.box.maxY
        }
        return output.joined(separator: "\n")
    }

    /// Joins all rows into one sequential text, re-joining words hyphenated across a line end.
    static func renderPlain(_ rows: [LayoutLine]) -> String {
        var text = ""
        for row in rows {
            let line = row.words.map(\.text).joined(separator: " ")
            if text.count >= 2, text.hasSuffix("-"), text.dropLast().last?.isLetter == true,
               line.first?.isLowercase == true {
                text.removeLast()
                text += line
            } else {
                text += (text.isEmpty ? "" : " ") + line
            }
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parses Tesseract's TSV output (`-c tessedit_create_tsv=1`) into one fragment per Tesseract line.
    static func parseTesseractTSV(_ tsv: String) -> [[LayoutWord]] {
        var lines: [String: [LayoutWord]] = [:]
        var order: [String] = []
        for row in tsv.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 12, fields[0] == "5",
                  let left = Double(fields[6]), let top = Double(fields[7]),
                  let width = Double(fields[8]), let height = Double(fields[9]) else { continue }
            let text = fields[11...].joined(separator: "\t").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let key = "\(fields[1]).\(fields[2]).\(fields[3]).\(fields[4])"
            if lines[key] == nil { order.append(key) }
            lines[key, default: []].append(LayoutWord(text: text, box: CGRect(x: left, y: top, width: width, height: height)))
        }
        return order.compactMap { lines[$0] }
    }

    /// A horizontal gap wider than this many characters separates columns rather than words.
    private static let columnGapInChars: CGFloat = 2.5

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
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
