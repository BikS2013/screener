import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: AppConfig
    @Published var message: String?
    @Published var isError = false
    let saved: AppConfig

    init(config: AppConfig) {
        draft = config
        saved = config
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    private let onSave: (AppConfig) throws -> Void
    private let onRecording: (Bool) -> Void
    var onClose: (() -> Void)?

    init(config: AppConfig, onSave: @escaping (AppConfig) throws -> Void, onRecording: @escaping (Bool) -> Void) {
        model = SettingsModel(config: config)
        self.onSave = onSave
        self.onRecording = onRecording
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "screener Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(
            model: model,
            save: { [weak self] in self?.save() },
            recordingChanged: onRecording))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func save() {
        do {
            try onSave(model.draft)
            model.isError = false
            model.message = "Saved to \(ConfigStore.fileURL.path)"
        } catch {
            model.isError = true
            model.message = error.localizedDescription
        }
    }

    func windowWillClose(_ notification: Notification) {
        onRecording(false)
        onClose?()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let save: () -> Void
    let recordingChanged: (Bool) -> Void

    private static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    private static let modifiers = ["shift", "option", "ctrl", "cmd"]

    private static func modifierTitle(_ name: String) -> String {
        ["shift": "⇧ Shift", "option": "⌥ Option", "ctrl": "⌃ Control", "cmd": "⌘ Command"][name] ?? name
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Hotkeys") {
                    LabeledContent("Start capture (global)") {
                        HotkeyField(value: $model.draft.hotkeys.activate, recordingChanged: recordingChanged)
                    }
                    LabeledContent("Cancel selection") {
                        HotkeyField(value: $model.draft.hotkeys.cancel, recordingChanged: recordingChanged)
                    }
                    LabeledContent("Show history (global)") {
                        HotkeyField(value: $model.draft.hotkeys.showHistory, recordingChanged: recordingChanged)
                    }
                    Text("Click a field, then press the new shortcut.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Keyboard selection (inside the overlay)") {
                    LabeledContent("Move up") { HotkeyField(value: $model.draft.keyboard.moveUp, recordingChanged: recordingChanged) }
                    LabeledContent("Move down") { HotkeyField(value: $model.draft.keyboard.moveDown, recordingChanged: recordingChanged) }
                    LabeledContent("Move left") { HotkeyField(value: $model.draft.keyboard.moveLeft, recordingChanged: recordingChanged) }
                    LabeledContent("Move right") { HotkeyField(value: $model.draft.keyboard.moveRight, recordingChanged: recordingChanged) }
                    Stepper(String(format: "Arrow step (default): %.0f pt", model.draft.keyboard.defaultStepPoints),
                            value: $model.draft.keyboard.defaultStepPoints, in: 1...500, step: 5)
                    Picker("Faster movement modifier", selection: $model.draft.keyboard.fasterModifier) {
                        ForEach(Self.modifiers, id: \.self) { Text(Self.modifierTitle($0)).tag($0) }
                    }
                    Stepper(String(format: "Faster step: %.0f pt", model.draft.keyboard.fasterStepPoints),
                            value: $model.draft.keyboard.fasterStepPoints, in: 1...2000, step: 10)
                    Picker("Fine movement modifier", selection: $model.draft.keyboard.fineModifier) {
                        ForEach(Self.modifiers, id: \.self) { Text(Self.modifierTitle($0)).tag($0) }
                    }
                    Stepper(String(format: "Fine step: %.0f pt", model.draft.keyboard.fineStepPoints),
                            value: $model.draft.keyboard.fineStepPoints, in: 1...100)
                    Picker("Extend selection modifier (text mode)", selection: $model.draft.keyboard.extendModifier) {
                        ForEach(Self.modifiers, id: \.self) { Text(Self.modifierTitle($0)).tag($0) }
                    }
                    LabeledContent("Set / clear anchor") { HotkeyField(value: $model.draft.keyboard.anchor, recordingChanged: recordingChanged) }
                    LabeledContent("Capture selection") { HotkeyField(value: $model.draft.keyboard.confirm, recordingChanged: recordingChanged) }
                    LabeledContent("Next screen") { HotkeyField(value: $model.draft.keyboard.nextScreen, recordingChanged: recordingChanged) }
                    LabeledContent("Toggle text mode") { HotkeyField(value: $model.draft.keyboard.toggleTextMode, recordingChanged: recordingChanged) }
                    LabeledContent("Toggle format (preserved / plain)") { HotkeyField(value: $model.draft.keyboard.toggleFormat, recordingChanged: recordingChanged) }
                    Toggle("Start in text mode (jump between detected lines)", isOn: $model.draft.keyboard.startInTextMode)
                }
                Section("Text recognition") {
                    Picker("Engine", selection: $model.draft.ocr.engine) {
                        Text("Auto (Vision; Tesseract when Greek is found)").tag(OCREngine.auto)
                        Text("Apple Vision only").tag(OCREngine.vision)
                        Text("Tesseract only").tag(OCREngine.tesseract)
                    }
                    TextField("Vision languages", text: Binding(
                        get: { model.draft.ocr.visionLanguages.joined(separator: ", ") },
                        set: { model.draft.ocr.visionLanguages = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    TextField("Tesseract languages", text: $model.draft.ocr.tesseractLanguages)
                    TextField("Tesseract binary", text: $model.draft.ocr.tesseractPath)
                    TextField("Tessdata folder", text: $model.draft.ocr.tessdataDir)
                    Stepper("Tesseract page segmentation: \(model.draft.ocr.tesseractPageSegMode)",
                            value: $model.draft.ocr.tesseractPageSegMode, in: 0...13)
                    Toggle("Vision language correction", isOn: $model.draft.ocr.languageCorrection)
                }
                Section("Output") {
                    Toggle("Format switch starts on \"Preserve screen format\" (off = plain sequential text)",
                           isOn: $model.draft.output.preserveFormat)
                    Toggle("Convert polytonic Greek to monotonic", isOn: $model.draft.output.greekMonotonic)
                    Toggle("Correct Greek look-alike letters and accents", isOn: $model.draft.output.greekCorrection)
                }
                Section("Feedback") {
                    Toggle("Show toast", isOn: $model.draft.feedback.toast)
                    Stepper(String(format: "Toast duration: %.1f s", model.draft.feedback.toastDurationSeconds),
                            value: $model.draft.feedback.toastDurationSeconds, in: 0.5...30, step: 0.5)
                    Toggle("Play sound", isOn: $model.draft.feedback.sound)
                    Picker("Sound", selection: $model.draft.feedback.soundName) {
                        ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: model.draft.feedback.soundName) { _, name in
                        NSSound(named: NSSound.Name(name))?.play()
                    }
                }
                Section("History & overlay") {
                    Stepper("History size: \(model.draft.history.size)", value: $model.draft.history.size, in: 1...500)
                    LabeledContent(String(format: "Overlay dimming: %.0f%%", model.draft.overlay.dimOpacity * 100)) {
                        Slider(value: $model.draft.overlay.dimOpacity, in: 0...0.9)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let message = model.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(model.isError ? Color.red : Color.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Button("Revert") {
                    model.draft = model.saved
                    model.message = nil
                }
                .disabled(model.draft == model.saved)
                Button("Save", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

/// Click to record: the next key press (with modifiers) becomes the hotkey.
struct HotkeyField: NSViewRepresentable {
    @Binding var value: String
    let recordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onRecordingChanged = recordingChanged
        view.onCapture = { combo in value = combo.canonical }
        view.value = value
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onCapture = { combo in value = combo.canonical }
        view.value = value
    }
}

final class HotkeyRecorderView: NSView {
    var value = "" { didSet { needsDisplay = true } }
    var onCapture: ((KeyCombo) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var recording = false {
        didSet {
            needsDisplay = true
            if recording != oldValue { onRecordingChanged?(recording) }
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        guard let combo = KeyCombo(event: event) else {
            NSSound.beep()
            return
        }
        onCapture?(combo)
        value = combo.canonical
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if recording {
            text = "Press shortcut…"
        } else if let combo = try? KeyCombo.parse(value) {
            text = combo.display
        } else {
            text = value.isEmpty ? "Click to record" : "⚠︎ \(value)"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }
}
