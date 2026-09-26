import AppKit

// Headless modes for scripting and verification:
//   Screener --check-config          validate ~/.tool-agents/screener/config.json
//   Screener --ocr-file <image> [--format preserved|plain]
//                                    run the configured OCR pipeline on an image file and print the text;
//                                    --format overrides output.preserveFormat for this run
let arguments = CommandLine.arguments

if arguments.contains("--check-config") {
    do {
        _ = try ConfigStore.load()
        print("OK: \(ConfigStore.fileURL.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let index = arguments.firstIndex(of: "--ocr-file") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("ERROR: --ocr-file needs an image path\n".utf8))
        exit(2)
    }
    let path = arguments[index + 1]
    var formatOverride: TextFormat?
    if let formatIndex = arguments.firstIndex(of: "--format") {
        guard arguments.count > formatIndex + 1, let parsed = TextFormat(rawValue: arguments[formatIndex + 1]) else {
            FileHandle.standardError.write(Data("ERROR: --format must be 'preserved' or 'plain'\n".utf8))
            exit(2)
        }
        formatOverride = parsed
    }
    // Runs on the main actor with the main queue free, because the Greek corrector uses NSSpellChecker.
    Task { @MainActor in
        do {
            let config = try ConfigStore.load()
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw OCRError.imageEncoding
            }
            let format = formatOverride ?? (config.output.preserveFormat ? .preserved : .plain)
            let result = try await OCR.recognize(image, pixelScale: 2, config: config, format: format)
            print("[engine: \(result.engine)\(result.warning.map { "; warning: \($0)" } ?? "")]")
            print(result.text)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
