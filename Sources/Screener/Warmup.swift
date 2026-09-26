import AppKit
import os

/// Apple Vision's accurate recogniser needs ~20 s the first time the system loads its model (the cost is
/// system-wide and comes back after the OS evicts the model). Running a tiny recognition in the background
/// at launch, and again whenever the overlay opens, keeps that delay out of real captures.
@MainActor
enum Warmup {
    private static let log = Logger(subsystem: "com.local.screener", category: "warmup")
    private static var running = false
    private static let sample: CGImage? = renderSample()

    /// Full pipeline warm-up (Vision, Tesseract, Greek spell checker, line detector) — used at launch.
    static func full(config: AppConfig) {
        start(name: "launch") {
            guard let image = sample else { return }
            _ = try await OCR.recognize(image, pixelScale: 2, config: config)
            _ = try await TextLineDetector.lines(in: image, screenFrame: CGRect(x: 0, y: 0, width: 400, height: 60))
        }
    }

    /// Vision-only re-warm, started when the overlay opens so it finishes while the user is still selecting.
    static func vision(config: AppConfig) {
        guard config.ocr.engine != .tesseract else { return }
        start(name: "overlay") {
            guard let image = sample else { return }
            _ = try await OCR.vision(image, config.ocr, preserveLineBreaks: true)
        }
    }

    private static func start(name: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard !running else { return }
        running = true
        let started = Date()
        Task { @MainActor in
            defer { running = false }
            do {
                try await work()
                log.info("\(name, privacy: .public) warm-up finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
            } catch {
                log.error("\(name, privacy: .public) warm-up failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A small image with Greek and Latin text, so every engine and the Greek corrector actually run.
    private static func renderSample() -> CGImage? {
        let size = NSSize(width: 400, height: 60)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 120, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("Screener warm-up\nΚαλημέρα κόσμε" as NSString).draw(at: NSPoint(x: 10, y: 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black,
        ])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
