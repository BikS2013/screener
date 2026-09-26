import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController()
    private var history = CaptureHistory(limit: 1)
    private var settingsController: SettingsWindowController?

    private var config: AppConfig?
    private var configError: Error?
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        overlay.onSelect = { [weak self] rect, screen, format in self?.process(rect: rect, screen: screen, format: format) }
        overlay.detectLines = { screen in
            let image = try await ScreenCapture.capture(rect: screen.frame, on: screen)
            return try await TextLineDetector.lines(in: image, screenFrame: screen.frame)
        }
        do {
            try ConfigStore.ensureDirectory()
        } catch {
            configError = error
        }
        reloadConfig(showErrors: true)
    }

    // MARK: - Configuration

    private func reloadConfig(showErrors: Bool) {
        HotKeyCenter.shared.unregisterAll()
        do {
            let loaded = try ConfigStore.load()
            config = loaded
            configError = nil
            history.limit = loaded.history.size
            try registerHotkeys(loaded)
            Warmup.full(config: loaded)
        } catch {
            HotKeyCenter.shared.unregisterAll()
            configError = error
            if showErrors {
                if case ConfigError.missingFile = error {
                    offerFirstRunSetup()
                } else {
                    presentError(error, title: "screener configuration problem")
                }
            }
        }
        updateStatusIcon()
    }

    private func registerHotkeys(_ config: AppConfig) throws {
        try HotKeyCenter.shared.register(try KeyCombo.parse(config.hotkeys.activate)) { [weak self] in
            self?.startCapture()
        }
        try HotKeyCenter.shared.register(try KeyCombo.parse(config.hotkeys.showHistory)) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    private func saveSettings(_ newConfig: AppConfig) throws {
        try ConfigStore.save(newConfig)
        reloadConfig(showErrors: false)
        if let configError { throw configError }
    }

    private func setHotkeysSuspended(_ suspended: Bool) {
        if suspended {
            HotKeyCenter.shared.unregisterAll()
        } else if let config, configError == nil {
            HotKeyCenter.shared.unregisterAll()
            try? registerHotkeys(config)
        }
    }

    private func updateStatusIcon() {
        let name = configError == nil ? "text.viewfinder" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "screener")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = configError?.localizedDescription ?? "screener — select screen text to copy"
    }

    // MARK: - Capture flow

    @objc private func startCapture() {
        guard let config, configError == nil else {
            presentError(configError ?? ConfigError.missingFile(ConfigStore.fileURL.path), title: "screener is not configured")
            return
        }
        guard !overlay.isActive, !isCapturing else { return }
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            presentMessage(title: "Screen Recording permission needed",
                           text: "Enable screener in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen screener.")
            return
        }
        do {
            overlay.show(dimOpacity: config.overlay.dimOpacity, bindings: try KeyboardBindings(config: config))
            Warmup.vision(config: config)
        } catch {
            presentError(error, title: "screener keyboard configuration problem")
        }
    }

    private func process(rect: CGRect, screen: NSScreen, format: TextFormat) {
        guard let config else { return }
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let image = try await ScreenCapture.capture(rect: rect, on: screen)
                let result = try await OCR.recognize(image, pixelScale: screen.backingScaleFactor, config: config, format: format)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    notify(config, "No text found", detail: result.warning, near: rect, on: screen, success: false)
                    return
                }
                Clipboard.copy(text)
                history.add(CaptureRecord(text: text, engine: result.engine, date: Date()))
                let lines = text.components(separatedBy: "\n").count
                notify(config, "Copied \(text.count) characters",
                       detail: result.warning
                           ?? "\(lines) line\(lines == 1 ? "" : "s") · \(format == .preserved ? "screen format" : "plain text") · \(result.engine)",
                       near: rect, on: screen, success: true)
            } catch {
                notify(config, "Capture failed", detail: error.localizedDescription, near: rect, on: screen, success: false)
            }
        }
    }

    private func notify(_ config: AppConfig, _ message: String, detail: String?, near rect: CGRect, on screen: NSScreen, success: Bool) {
        if config.feedback.sound {
            (success ? NSSound(named: NSSound.Name(config.feedback.soundName)) : NSSound(named: "Basso"))?.play()
        }
        // Failures are always shown, even with toasts disabled, so errors are never silent.
        if config.feedback.toast || !success {
            Toast.show(message, detail: detail, near: rect, on: screen,
                       duration: success ? config.feedback.toastDurationSeconds : max(config.feedback.toastDurationSeconds, 4))
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let configError {
            let errorItem = item("⚠︎ Configuration problem…", #selector(showConfigError))
            errorItem.toolTip = configError.localizedDescription
            menu.addItem(errorItem)
            if case ConfigError.missingFile = configError {
                menu.addItem(item("Create Config from Example", #selector(createConfigFromExample)))
            }
            menu.addItem(.separator())
        }

        let captureTitle: String
        if let config, let combo = try? KeyCombo.parse(config.hotkeys.activate) {
            captureTitle = "Capture Text\t\(combo.display)"
        } else {
            captureTitle = "Capture Text"
        }
        let capture = item(captureTitle, #selector(startCapture))
        capture.isEnabled = configError == nil
        menu.addItem(capture)
        menu.addItem(.separator())

        let header = NSMenuItem(title: history.items.isEmpty ? "No recent captures" : "Recent Captures — click to copy", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        for (index, record) in history.items.enumerated() {
            let preview = record.text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let title = preview.count > 60 ? String(preview.prefix(60)) + "…" : preview
            let entry = item(title, #selector(copyHistoryItem(_:)))
            entry.tag = index
            entry.toolTip = "\(record.engine) · \(formatter.localizedString(for: record.date, relativeTo: Date()))\n\n\(record.text)"
            menu.addItem(entry)
        }
        if !history.items.isEmpty {
            menu.addItem(item("Clear History", #selector(clearHistory)))
        }
        menu.addItem(.separator())

        let settings = item("Settings…", #selector(openSettings), key: ",")
        settings.isEnabled = config != nil
        menu.addItem(settings)
        menu.addItem(item("Reload Config", #selector(reloadConfigAction)))
        menu.addItem(item("Open Config Folder", #selector(openConfigFolder)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let info = Bundle.main.infoDictionary
        if let version = info?["CFBundleShortVersionString"] as? String, let build = info?["CFBundleVersion"] as? String {
            let versionItem = NSMenuItem(title: "screener \(version) (build \(build))", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }
        menu.addItem(item("Quit screener", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard history.items.indices.contains(sender.tag) else { return }
        Clipboard.copy(history.items[sender.tag].text)
    }

    @objc private func clearHistory() { history.clear() }

    @objc private func showConfigError() {
        if let configError { presentError(configError, title: "screener configuration problem") }
    }

    @objc private func reloadConfigAction() { reloadConfig(showErrors: true) }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL.deletingLastPathComponent()])
    }

    /// First launch: no config yet. The user decides whether to create it from the bundled example.
    private func offerFirstRunSetup() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Welcome to screener"
        alert.informativeText = "screener needs a configuration file at \(ConfigStore.fileURL.path).\n\n"
            + "\"Create Config from Example\" writes the example configuration (⌃⌥⌘T to capture, ⎋ to cancel) "
            + "and installs the Greek and English OCR data next to it. You can change everything later in Settings."
        alert.addButton(withTitle: "Create Config from Example")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            createConfigFromExample()
        }
    }

    @objc private func createConfigFromExample() {
        guard let example = Bundle.main.url(forResource: "config.example", withExtension: "json") else {
            presentMessage(title: "Example not found", text: "config.example.json is missing from the app bundle. Copy it from the project folder to \(ConfigStore.fileURL.path).")
            return
        }
        do {
            if let tessdata = Bundle.main.url(forResource: "tessdata", withExtension: nil) {
                try ConfigStore.installBundledTessdata(
                    from: tessdata, into: ConfigStore.directory.appendingPathComponent("tessdata", isDirectory: true))
            }
            try ConfigStore.createFromExample(example)
            reloadConfig(showErrors: true)
        } catch {
            presentError(error, title: "Could not create the configuration")
        }
    }

    @objc private func openSettings() {
        guard let config else { return }
        if settingsController == nil {
            let controller = SettingsWindowController(
                config: config,
                onSave: { [weak self] in try self?.saveSettings($0) },
                onRecording: { [weak self] in self?.setHotkeysSuspended($0) })
            controller.onClose = { [weak self] in self?.settingsController = nil }
            settingsController = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError(error, title: "Could not change the login item")
        }
    }

    // MARK: - Alerts

    private func presentError(_ error: Error, title: String) {
        presentMessage(title: title, text: error.localizedDescription)
    }

    private func presentMessage(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }
}
