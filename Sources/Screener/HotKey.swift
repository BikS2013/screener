import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, written in config as e.g. "ctrl+option+cmd+t" or "escape".
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    enum ParseError: LocalizedError {
        case empty
        case unknownModifier(String)
        case unknownKey(String)

        var errorDescription: String? {
            switch self {
            case .empty: return "hotkey is empty."
            case .unknownModifier(let m): return "unknown modifier '\(m)' (use cmd, ctrl, option, shift)."
            case .unknownKey(let k): return "unknown key '\(k)'."
            }
        }
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    init?(event: NSEvent) {
        guard KeyNames.name(for: UInt32(event.keyCode)) != nil else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
    }

    static func parse(_ text: String) throws -> KeyCombo {
        let tokens = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = tokens.last, !keyName.isEmpty else { throw ParseError.empty }
        var mods: NSEvent.ModifierFlags = []
        for token in tokens.dropLast() {
            mods.insert(try parseModifier(token))
        }
        guard let code = KeyNames.codes[keyName] else { throw ParseError.unknownKey(keyName) }
        return KeyCombo(keyCode: code, modifiers: mods)
    }

    static func parseModifier(_ text: String) throws -> NSEvent.ModifierFlags {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "cmd", "command": return .command
        case "ctrl", "control": return .control
        case "opt", "option", "alt": return .option
        case "shift": return .shift
        default: throw ParseError.unknownModifier(text)
        }
    }

    /// Canonical config spelling, e.g. "ctrl+option+cmd+t".
    var canonical: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(KeyNames.name(for: keyCode) ?? "?")
        return parts.joined(separator: "+")
    }

    /// Menu-style rendering, e.g. "⌃⌥⌘T".
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyNames.symbol(for: keyCode)
    }

    var isFunctionKey: Bool {
        guard let name = KeyNames.name(for: keyCode), name.hasPrefix("f") else { return false }
        return Int(name.dropFirst()) != nil
    }

    /// Global hotkeys must not swallow ordinary typing.
    var isSafeGlobalHotkey: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty || isFunctionKey
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode && event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }
}

enum KeyNames {
    static let codes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26,
            "minus": 27, "8": 28, "0": 29, "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33,
            "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
            "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48,
            "space": 49, "grave": 50, "delete": 51, "escape": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
            "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
            "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        map["esc"] = 53
        map["enter"] = 36
        return map
    }()

    private static let preferredNames: [UInt32: String] = {
        var reverse: [UInt32: String] = [:]
        for (name, code) in codes where name != "esc" && name != "enter" { reverse[code] = name }
        return reverse
    }()

    private static let symbols: [String: String] = [
        "escape": "⎋", "return": "↩", "tab": "⇥", "space": "Space", "delete": "⌫",
        "forwarddelete": "⌦", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟", "equal": "=", "minus": "-",
        "leftbracket": "[", "rightbracket": "]", "quote": "'", "semicolon": ";", "backslash": "\\",
        "comma": ",", "slash": "/", "period": ".", "grave": "`",
    ]

    static func name(for code: UInt32) -> String? { preferredNames[code] }

    static func symbol(for code: UInt32) -> String {
        guard let name = name(for: code) else { return "?" }
        return symbols[name] ?? name.uppercased()
    }
}

/// Registers system-wide hotkeys through Carbon (needs no Accessibility permission).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum RegistrationError: LocalizedError {
        case failed(String, OSStatus)
        var errorDescription: String? {
            switch self {
            case .failed(let combo, let status) where status == OSStatus(eventHotKeyExistsErr):
                return "The hotkey \(combo) is already taken by another application."
            case .failed(let combo, let status):
                return "Could not register the hotkey \(combo) (OSStatus \(status))."
            }
        }
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register(_ combo: KeyCombo, handler: @escaping () -> Void) throws {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343_524E), id: id) // "SCRN"
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw RegistrationError.failed(combo.display, status) }
        refs[id] = ref
        handlers[id] = handler
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &eventHandler)
    }
}

private func hotKeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    // Carbon delivers hotkey events on the main thread.
    DispatchQueue.main.async { HotKeyCenter.shared.fire(id: hotKeyID.id) }
    return noErr
}
