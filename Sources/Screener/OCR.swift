import AppKit
import CoreImage
import Foundation
import Vision

struct OCRResult {
    let text: String
    let engine: String
    /// Non-fatal problem worth showing to the user (e.g. Tesseract failed in auto mode).
    let warning: String?
}

enum OCRError: LocalizedError {
    case tesseractLaunch(String)
    case tesseractFailed(Int32, String)
    case imageEncoding

    var errorDescription: String? {
        switch self {
        case .tesseractLaunch(let reason): return "Could not start Tesseract: \(reason)"
        case .tesseractFailed(let code, let stderr): return "Tesseract exited with status \(code): \(stderr)"
        case .imageEncoding: return "Could not prepare the captured image for OCR."
        }
    }
}

enum OCR {
    /// - Parameters:
    ///   - pixelScale: pixels per point of the captured image (used to upscale 1x captures for Tesseract).
    ///   - format: preserved on-screen layout or one sequential text; chosen per capture in the overlay.
    static func recognize(_ image: CGImage, pixelScale: CGFloat, config: AppConfig, format: TextFormat) async throws -> OCRResult {
                let result: OCRResult
        switch config.ocr.engine {
        case .vision:
            result = OCRResult(text: try await vision(image, config.ocr, format: format),
                               engine: "Vision", warning: nil)
        case .tesseract:
            result = OCRResult(text: try await tesseract(image, pixelScale: pixelScale, config.ocr, format: format),
                               engine: "Tesseract", warning: nil)
        case .auto:
            // Vision is the stronger engine for Latin script but cannot read Greek, so both run in
            // parallel and Tesseract wins whenever it sees Greek characters.
            async let visionText = vision(image, config.ocr, format: format)
            async let tesseractText = tesseract(image, pixelScale: pixelScale, config.ocr, format: format)
            var tesseractOutput: String?
            var tesseractError: Error?
            do {
                tesseractOutput = try await tesseractText
            } catch {
                tesseractError = error
            }
            let visionOutput = try await visionText
            if let tesseractOutput, GreekText.containsGreek(tesseractOutput) {
                result = OCRResult(text: tesseractOutput, engine: "Tesseract", warning: nil)
            } else {
                result = OCRResult(text: visionOutput, engine: "Vision",
                                   warning: tesseractError.map { "Greek detection unavailable — \($0.localizedDescription)" })
            }
        }
        var text = result.text
        if config.output.greekMonotonic {
            text = GreekText.toMonotonic(text)
        }
        if config.output.greekCorrection, result.engine == "Tesseract", GreekText.containsGreek(text) {
            let raw = text
            text = await MainActor.run { GreekCorrector(spell: SystemSpellChecker()).correct(raw) }
        }
        return OCRResult(text: text, engine: result.engine, warning: result.warning)
    }

    static func vision(_ image: CGImage, _ ocr: OCRConfig, format: TextFormat) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ocr.visionLanguages
                request.usesLanguageCorrection = ocr.languageCorrection
                request.automaticallyDetectsLanguage = true
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let size = CGSize(width: image.width, height: image.height)
                    let fragments = (request.results ?? []).compactMap { observation -> [LayoutWord]? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return words(of: candidate, lineBox: observation.boundingBox, imageSize: size)
                    }
                    continuation.resume(returning: TextLayout.render(TextLayout.rows(from: fragments), format: format))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func tesseract(_ image: CGImage, pixelScale: CGFloat, _ ocr: OCRConfig, format: TextFormat) async throws -> String {
        let png = try ImagePrep.pngForTesseract(image, upscale: pixelScale < 2 ? 2 : 1)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let tsv = try runTesseract(png: png, ocr)
                    let rows = TextLayout.rows(from: TextLayout.parseTesseractTSV(tsv))
                    continuation.resume(returning: TextLayout.render(rows, format: format))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Splits a Vision line into words with their own boxes (converted to top-left pixel coordinates),
    /// so columns inside one observation can be aligned. Falls back to a proportional split when Vision
    /// cannot box a word.
    private static func words(of candidate: VNRecognizedText, lineBox: CGRect, imageSize: CGSize) -> [LayoutWord] {
        func pixels(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX * imageSize.width, y: (1 - box.maxY) * imageSize.height,
                   width: box.width * imageSize.width, height: box.height * imageSize.height)
        }
        let text = candidate.string
        let total = max(text.count, 1)
        return text.split(separator: " ").map { word in
            let range = word.startIndex..<word.endIndex
            if let box = (try? candidate.boundingBox(for: range))?.boundingBox, box.width > 0 {
                return LayoutWord(text: String(word), box: pixels(box))
            }
            let start = CGFloat(text.distance(from: text.startIndex, to: word.startIndex)) / CGFloat(total)
            let share = CGFloat(word.count) / CGFloat(total)
            let box = CGRect(x: lineBox.minX + start * lineBox.width, y: lineBox.minY,
                             width: share * lineBox.width, height: lineBox.height)
            return LayoutWord(text: String(word), box: pixels(box))
        }
    }

    private static func runTesseract(png: Data, _ ocr: OCRConfig) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ConfigStore.expandTilde(ocr.tesseractPath))
        process.arguments = [
            "stdin", "stdout",
            "-l", ocr.tesseractLanguages,
            "--psm", String(ocr.tesseractPageSegMode),
            "--tessdata-dir", ConfigStore.expandTilde(ocr.tessdataDir),
            "-c", "tessedit_create_tsv=1", // word boxes, needed to rebuild the on-screen layout
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["OMP_THREAD_LIMIT"] = "1" // multithreading slows Tesseract down on small images
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw OCRError.tesseractLaunch(error.localizedDescription)
        }

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        stdin.fileHandleForWriting.write(png)
        try? stdin.fileHandleForWriting.close()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw OCRError.tesseractFailed(process.terminationStatus, message)
        }
        return String(decoding: outData, as: UTF8.self)
    }
}

/// Finds text-line rectangles on a whole screen for keyboard navigation. Uses Vision's fast level:
/// the recognised strings are ignored (it cannot read Greek), only the line boxes matter.
enum TextLineDetector {
    /// Returns line rectangles in global AppKit coordinates.
    static func lines(in image: CGImage, screenFrame: CGRect) async throws -> [CGRect] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let rects = (request.results ?? []).map { observation -> CGRect in
                        let box = observation.boundingBox
                        return CGRect(x: screenFrame.minX + box.minX * screenFrame.width,
                                      y: screenFrame.minY + box.minY * screenFrame.height,
                                      width: box.width * screenFrame.width,
                                      height: box.height * screenFrame.height)
                    }
                    continuation.resume(returning: rects)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ImagePrep {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Grayscale, dark-on-light, optionally upscaled, padded PNG — the input Tesseract reads best.
    static func pngForTesseract(_ image: CGImage, upscale: CGFloat) throws -> Data {
        var ci = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        if averageLuminance(ci) < 0.5 {
            ci = ci.applyingFilter("CIColorInvert") // dark mode: Tesseract wants dark text on a light background
        }
        if upscale > 1 {
            ci = ci.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: upscale, kCIInputAspectRatioKey: 1])
        }
        let padded = ci.extent.insetBy(dx: -12, dy: -12)
        ci = ci.composited(over: CIImage(color: .white).cropped(to: padded))
        guard let cg = context.createCGImage(ci, from: padded),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw OCRError.imageEncoding
        }
        return png
    }

    static func averageLuminance(_ image: CIImage) -> CGFloat {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (0.299 * CGFloat(pixel[0]) + 0.587 * CGFloat(pixel[1]) + 0.114 * CGFloat(pixel[2])) / 255
    }
}
