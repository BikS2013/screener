import AppKit

/// Keyboard bindings for the overlay, resolved from `AppConfig.hotkeys.cancel` and `AppConfig.keyboard`.
struct KeyboardBindings {
    let up, down, left, right: KeyCombo
    let defaultStep: CGFloat
    let fineModifier: NSEvent.ModifierFlags
    let fineStep: CGFloat
    let fasterModifier: NSEvent.ModifierFlags
    let fasterStep: CGFloat
    let extendModifier: NSEvent.ModifierFlags
    let anchor, confirm, nextScreen, toggleTextMode, toggleFormat, cancel: KeyCombo
    let startInTextMode: Bool
    let startFormat: TextFormat

    init(config: AppConfig) throws {
        let k = config.keyboard
        up = try KeyCombo.parse(k.moveUp)
        down = try KeyCombo.parse(k.moveDown)
        left = try KeyCombo.parse(k.moveLeft)
        right = try KeyCombo.parse(k.moveRight)
        defaultStep = CGFloat(k.defaultStepPoints)
        fineModifier = try KeyCombo.parseModifier(k.fineModifier)
        fineStep = CGFloat(k.fineStepPoints)
        fasterModifier = try KeyCombo.parseModifier(k.fasterModifier)
        fasterStep = CGFloat(k.fasterStepPoints)
        extendModifier = try KeyCombo.parseModifier(k.extendModifier)
        anchor = try KeyCombo.parse(k.anchor)
        confirm = try KeyCombo.parse(k.confirm)
        nextScreen = try KeyCombo.parse(k.nextScreen)
        toggleTextMode = try KeyCombo.parse(k.toggleTextMode)
        toggleFormat = try KeyCombo.parse(k.toggleFormat)
        cancel = try KeyCombo.parse(config.hotkeys.cancel)
        startInTextMode = k.startInTextMode
        startFormat = config.output.preserveFormat ? .preserved : .plain
    }

    var arrowsDisplay: String { [up, down, left, right].map(\.display).joined() }

    /// Crosshair step for the modifiers held with an arrow key; nil when the combination is not a move.
    func step(for modifiers: NSEvent.ModifierFlags) -> CGFloat? {
        switch modifiers {
        case []: return defaultStep
        case fasterModifier: return fasterStep
        case fineModifier: return fineStep
        default: return nil
        }
    }
}

enum Direction { case up, down, left, right }

/// Spatial navigation between text-line rectangles (AppKit coordinates, y grows upwards).
enum LineNavigator {
    static func readingOrder(_ rects: [CGRect]) -> [CGRect] {
        rects.sorted { a, b in
            if abs(a.midY - b.midY) < 0.5 * min(a.height, b.height) { return a.minX < b.minX }
            return a.midY > b.midY
        }
    }

    static func nearest(to point: CGPoint, in rects: [CGRect]) -> Int? {
        rects.indices.min { distance(point, rects[$0]) < distance(point, rects[$1]) }
    }

    /// The closest rectangle in `direction`, preferring ones aligned with `current` (same column / same row).
    static func neighbour(of index: Int, in rects: [CGRect], direction: Direction) -> Int? {
        let current = rects[index]
        var best: (index: Int, score: CGFloat)?
        for (i, candidate) in rects.enumerated() where i != index {
            let primary: CGFloat
            let secondary: CGFloat
            switch direction {
            case .down:
                primary = current.midY - candidate.midY
                secondary = gap(current.minX...current.maxX, candidate.minX...candidate.maxX)
            case .up:
                primary = candidate.midY - current.midY
                secondary = gap(current.minX...current.maxX, candidate.minX...candidate.maxX)
            case .right:
                primary = candidate.midX - current.midX
                secondary = gap(current.minY...current.maxY, candidate.minY...candidate.maxY)
            case .left:
                primary = current.midX - candidate.midX
                secondary = gap(current.minY...current.maxY, candidate.minY...candidate.maxY)
            }
            let threshold = (direction == .up || direction == .down) ? current.height * 0.3 : 1
            guard primary > threshold else { continue }
            let score = primary + 3 * secondary
            if best == nil || score < best!.score { best = (i, score) }
        }
        return best?.index
    }

    /// The area covered by a multi-line selection from line `a` to line `b`: both end lines plus every line
    /// lying vertically between them that overlaps the selection horizontally, each at its full width. Repeats
    /// until stable, so a long middle line widens the selection, while a separate column beside it (no
    /// horizontal overlap) stays out.
    static func span(from a: Int, to b: Int, in rects: [CGRect]) -> CGRect {
        var area = rects[a].union(rects[b])
        var included: Set<Int> = [a, b]
        var grew = true
        while grew {
            grew = false
            for (i, rect) in rects.enumerated() where !included.contains(i) {
                let verticallyInside = rect.midY >= area.minY && rect.midY <= area.maxY
                let overlapsHorizontally = rect.maxX > area.minX && rect.minX < area.maxX
                if verticallyInside, overlapsHorizontally {
                    included.insert(i)
                    area = area.union(rect)
                    grew = true
                }
            }
        }
        return area
    }

    private static func gap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
        max(0, max(a.lowerBound, b.lowerBound) - min(a.upperBound, b.upperBound))
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}

/// One nearly transparent, borderless window per screen. The user selects with the mouse (drag) or the
/// keyboard: in free mode arrows move a crosshair and an anchor stretches the rectangle; in text mode
/// arrows jump between the text lines detected on the screen.
@MainActor
final class OverlayController {
    enum Mode { case free, text }

    struct ViewState {
        var lines: [CGRect] = []
        var focused: CGRect?
        var selection: CGRect?
        var cursor: CGPoint?
        var status: String?
        var hint: String?
        /// The format switch; shown on the active screen, also while dragging.
        var formatSwitch: String?
    }

    /// Called with the selection in global AppKit coordinates, the screen it was drawn on and the chosen format.
    var onSelect: ((CGRect, NSScreen, TextFormat) -> Void)?
    var onCancel: (() -> Void)?
    /// Returns the text-line rectangles (global coordinates) visible on a screen.
    var detectLines: ((NSScreen) async throws -> [CGRect])?

    var isActive: Bool { !windows.isEmpty }

    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var screens: [NSScreen] = []
    private var bindings: KeyboardBindings?
    private var session = 0

    private var activeIndex = 0
    private var mode: Mode = .free
    private var cursor: CGPoint = .zero
    private var anchor: CGPoint?
    private var keyboardUsed = false
    private var mouseDragging = false
    private var format: TextFormat = .preserved

    private var lines: [Int: [CGRect]] = [:]
    private var detecting: Set<Int> = []
    private var detectionErrors: [Int: String] = [:]
    private var focusedLine: Int?
    private var anchorLine: Int?
    private var anchorIsSticky = false

    private static let minimumSize: CGFloat = 4
    private static let linePadding: CGFloat = 3

    func show(dimOpacity: CGFloat, bindings: KeyboardBindings) {
        guard !isActive else { return }
        session += 1
        self.bindings = bindings
        screens = NSScreen.screens
        cursor = NSEvent.mouseLocation
        activeIndex = screens.firstIndex { $0.frame.contains(cursor) } ?? 0
        mode = bindings.startInTextMode ? .text : .free
        format = bindings.startFormat
        resetSelectionState()
        lines = [:]
        detecting = []
        detectionErrors = [:]
        keyboardUsed = false

        for (index, screen) in screens.enumerated() {
            let window = OverlayWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.dimOpacity = dimOpacity
            view.controller = self
            view.screenIndex = index
            window.contentView = view
            windows.append(window)
            views.append(view)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        focusActiveWindow()
        NSCursor.crosshair.set()
        if mode == .text { ensureLines(on: activeIndex) }
    }

    func dismiss() {
        session += 1
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
    }

    // MARK: - State for drawing

    func state(for index: Int) -> ViewState {
        guard let bindings else { return ViewState() }
        let origin = screens[index].frame.origin
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }
        var state = ViewState()
        guard index == activeIndex else { return state }

        switch mode {
        case .free:
            if let anchor { state.selection = local(Self.rect(anchor, cursor)) }
            if keyboardUsed { state.cursor = CGPoint(x: cursor.x - origin.x, y: cursor.y - origin.y) }
            state.hint = "Drag with the mouse, or \(bindings.arrowsDisplay) move (\(Self.symbol(bindings.fasterModifier)) faster, \(Self.symbol(bindings.fineModifier)) fine) · "
                + "\(bindings.anchor.display) anchor · \(bindings.confirm.display) capture · "
                + "\(bindings.toggleTextMode.display) text mode · \(bindings.nextScreen.display) next screen · \(bindings.cancel.display) cancel"
        case .text:
            let screenLines = lines[index] ?? []
            state.lines = screenLines.map(local)
            if let focusedLine, screenLines.indices.contains(focusedLine) {
                state.focused = local(screenLines[focusedLine])
                if let selection = textSelection() { state.selection = local(selection) }
            }
            if detecting.contains(index) {
                state.status = "Finding text…"
            } else if let error = detectionErrors[index] {
                state.status = "Text detection failed: \(error)"
            } else if lines[index]?.isEmpty == true {
                state.status = "No text found on this screen"
            }
            state.hint = "\(bindings.arrowsDisplay) jump between lines · \(Self.symbol(bindings.extendModifier))+arrows extend · "
                + "\(bindings.anchor.display) anchor · \(bindings.confirm.display) capture · "
                + "\(bindings.toggleTextMode.display) free mode · \(bindings.nextScreen.display) next screen · \(bindings.cancel.display) cancel"
        }
        if mouseDragging { state.hint = nil }
        state.formatSwitch = (format == .preserved ? "◉ Preserve screen format   ○ Plain text" : "○ Preserve screen format   ◉ Plain text")
            + "   (\(bindings.toggleFormat.display) or click)"
        return state
    }

    // MARK: - Mouse

    func mouseMoved(to point: CGPoint, on index: Int) {
        guard !mouseDragging else { return }
        cursor = point
        if index != activeIndex {
            activeIndex = index
            resetSelectionState()
            if mode == .text { ensureLines(on: index) }
            refresh()
        }
    }

    func mouseDragBegan(on index: Int) {
        mouseDragging = true
        if index != activeIndex {
            activeIndex = index
            resetSelectionState()
        }
        anchor = nil
        refresh()
    }

    func mouseDragEnded(globalRect: CGRect, on index: Int, modifiers: NSEvent.ModifierFlags) {
        mouseDragging = false
        if globalRect.width >= Self.minimumSize, globalRect.height >= Self.minimumSize {
            finish(globalRect, on: index)
        } else if mode == .text, let screenLines = lines[index],
                  let hit = screenLines.firstIndex(where: { $0.insetBy(dx: -2, dy: -2).contains(globalRect.origin) }) {
            // A click on a detected line focuses it; with the extend modifier it extends the selection.
            let extending = bindings.map { !$0.extendModifier.isEmpty && modifiers.contains($0.extendModifier) } ?? false
            if extending, anchorLine == nil { anchorLine = focusedLine }
            if !extending, !anchorIsSticky { anchorLine = nil }
            focusedLine = hit
            refresh()
        } else {
            refresh()
        }
    }

    // MARK: - Keyboard

    func handleKey(_ event: NSEvent) -> Bool {
        guard let b = bindings else { return false }
        if b.cancel.matches(event) {
            cancel()
        } else if b.toggleTextMode.matches(event) {
            toggleMode()
        } else if b.toggleFormat.matches(event) {
            toggleFormat()
        } else if b.nextScreen.matches(event) {
            switchToNextScreen()
        } else if b.confirm.matches(event) {
            confirm()
        } else if b.anchor.matches(event) {
            toggleAnchor()
        } else if let (direction, modifiers) = direction(for: event, bindings: b) {
            switch mode {
            case .free: moveCursor(direction, step: b.step(for: modifiers) ?? b.defaultStep)
            case .text: moveFocus(direction, extending: !b.extendModifier.isEmpty && modifiers == b.extendModifier)
            }
        } else {
            return false
        }
        return true
    }

    private func direction(for event: NSEvent, bindings b: KeyboardBindings) -> (Direction, NSEvent.ModifierFlags)? {
        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        switch mode {
        case .free: guard b.step(for: modifiers) != nil else { return nil }
        case .text: guard modifiers.isEmpty || modifiers == b.extendModifier else { return nil }
        }
        let code = UInt32(event.keyCode)
        let mapping: [(KeyCombo, Direction)] = [(b.up, .up), (b.down, .down), (b.left, .left), (b.right, .right)]
        guard let direction = mapping.first(where: { $0.0.keyCode == code })?.1 else { return nil }
        return (direction, modifiers)
    }

    private func cancel() {
        dismiss()
        onCancel?()
    }

    func toggleFormat() {
        format = format == .preserved ? .plain : .preserved
        refresh()
    }

    private func toggleMode() {
        resetSelectionState()
        switch mode {
        case .free:
            mode = .text
            ensureLines(on: activeIndex)
        case .text:
            if let focusedLine, let rect = lines[activeIndex]?[focusedLine] {
                cursor = CGPoint(x: rect.midX, y: rect.midY)
            }
            mode = .free
        }
        refresh()
    }

    private func switchToNextScreen() {
        guard screens.count > 1 else { return NSSound.beep() }
        activeIndex = (activeIndex + 1) % screens.count
        let frame = screens[activeIndex].frame
        cursor = CGPoint(x: frame.midX, y: frame.midY)
        resetSelectionState()
        focusActiveWindow()
        if mode == .free {
            keyboardUsed = true
            warpPointer(to: cursor)
        } else {
            ensureLines(on: activeIndex)
        }
        refresh()
    }

    private func confirm() {
        switch mode {
        case .free:
            guard let anchor else { return NSSound.beep() }
            let rect = Self.rect(anchor, cursor)
            guard rect.width >= Self.minimumSize, rect.height >= Self.minimumSize else { return NSSound.beep() }
            finish(rect, on: activeIndex)
        case .text:
            guard let selection = textSelection() else { return NSSound.beep() }
            finish(selection, on: activeIndex)
        }
    }

    private func toggleAnchor() {
        switch mode {
        case .free:
            keyboardUsed = true
            anchor = anchor == nil ? cursor : nil
        case .text:
            guard focusedLine != nil else { return NSSound.beep() }
            if anchorIsSticky {
                anchorLine = nil
                anchorIsSticky = false
            } else {
                anchorLine = focusedLine
                anchorIsSticky = true
            }
        }
        refresh()
    }

    private func moveCursor(_ direction: Direction, step: CGFloat) {
        keyboardUsed = true
        switch direction {
        case .up: cursor.y += step
        case .down: cursor.y -= step
        case .left: cursor.x -= step
        case .right: cursor.x += step
        }
        let frame = screens[activeIndex].frame
        cursor.x = min(max(cursor.x, frame.minX), frame.maxX - 1)
        cursor.y = min(max(cursor.y, frame.minY), frame.maxY - 1)
        warpPointer(to: cursor)
        refresh()
    }

    private func moveFocus(_ direction: Direction, extending: Bool) {
        guard let screenLines = lines[activeIndex], !screenLines.isEmpty else { return NSSound.beep() }
        guard let current = focusedLine else {
            focusedLine = LineNavigator.nearest(to: cursor, in: screenLines)
            return refresh()
        }
        if extending, anchorLine == nil { anchorLine = current }
        if !extending, !anchorIsSticky { anchorLine = nil }
        if let next = LineNavigator.neighbour(of: current, in: screenLines, direction: direction) {
            focusedLine = next
        } else {
            NSSound.beep()
        }
        refresh()
    }

    // MARK: - Helpers

    private func textSelection() -> CGRect? {
        guard let focusedLine, let screenLines = lines[activeIndex], screenLines.indices.contains(focusedLine) else { return nil }
        let area = LineNavigator.span(from: anchorLine ?? focusedLine, to: focusedLine, in: screenLines)
        return area.insetBy(dx: -Self.linePadding, dy: -Self.linePadding).intersection(screens[activeIndex].frame)
    }

    private func ensureLines(on index: Int) {
        if lines[index] != nil {
            if focusedLine == nil, let screenLines = lines[index] {
                focusedLine = LineNavigator.nearest(to: cursor, in: screenLines)
            }
            return
        }
        guard !detecting.contains(index), let detectLines else { return }
        detecting.insert(index)
        refresh()
        let screen = screens[index]
        let current = session
        Task { @MainActor in
            do {
                let found = try await detectLines(screen)
                guard current == session else { return }
                lines[index] = LineNavigator.readingOrder(found)
            } catch {
                guard current == session else { return }
                detectionErrors[index] = error.localizedDescription
                lines[index] = []
            }
            detecting.remove(index)
            if mode == .text, activeIndex == index, focusedLine == nil, let screenLines = lines[index] {
                focusedLine = LineNavigator.nearest(to: cursor, in: screenLines)
            }
            refresh()
        }
    }

    private func resetSelectionState() {
        anchor = nil
        anchorLine = nil
        anchorIsSticky = false
        focusedLine = nil
    }

    private func finish(_ rect: CGRect, on index: Int) {
        let screen = screens[index]
        let chosen = format
        dismiss()
        onSelect?(rect, screen, chosen)
    }

    private func focusActiveWindow() {
        guard windows.indices.contains(activeIndex) else { return }
        windows[activeIndex].makeKey()
        windows[activeIndex].makeFirstResponder(views[activeIndex])
    }

    private func refresh() {
        views.forEach { $0.needsDisplay = true }
    }

    /// Moves the real pointer with the keyboard cursor so mouse and keyboard stay in sync.
    private func warpPointer(to point: CGPoint) {
        guard let primary = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private static func symbol(_ modifier: NSEvent.ModifierFlags) -> String {
        switch modifier {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        default: return ""
        }
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    var dimOpacity: CGFloat = 0
    weak var controller: OverlayController?
    var screenIndex = 0

    private var start: CGPoint?
    private var current: CGPoint?
    /// Where the format switch was last drawn (view coordinates); a click there flips it.
    private var formatSwitchRect: CGRect?

    private var dragRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        MainActor.assumeIsolated { controller?.mouseMoved(to: globalPoint(event), on: screenIndex) }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        MainActor.assumeIsolated { controller?.mouseMoved(to: globalPoint(event), on: screenIndex) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = clamp(convert(event.locationInWindow, from: nil))
        if let formatSwitchRect, formatSwitchRect.contains(point) {
            MainActor.assumeIsolated { controller?.toggleFormat() }
            return
        }
        start = point
        current = point
        MainActor.assumeIsolated { controller?.mouseDragBegan(on: screenIndex) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        current = clamp(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = dragRect, let window else { return }
        start = nil
        current = nil
        needsDisplay = true
        let global = window.convertToScreen(rect)
        let modifiers = event.modifierFlags
        MainActor.assumeIsolated { controller?.mouseDragEnded(globalRect: global, on: screenIndex, modifiers: modifiers) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let cancelled = MainActor.assumeIsolated { () -> Bool in
            guard let controller else { return false }
            controller.dismiss()
            controller.onCancel?()
            return true
        }
        if !cancelled { super.rightMouseDown(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        let handled = MainActor.assumeIsolated { controller?.handleKey(event) ?? false }
        if !handled { super.keyDown(with: event) }
    }

    // Lets combos with ⌘ reach the overlay instead of the (empty) main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true else { return false }
        let handled = MainActor.assumeIsolated { controller?.handleKey(event) ?? false }
        return handled || super.performKeyEquivalent(with: event)
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        bounds.fill()
        let state = MainActor.assumeIsolated { controller?.state(for: screenIndex) } ?? OverlayController.ViewState()

        for line in state.lines {
            let path = NSBezierPath(roundedRect: line.insetBy(dx: -2, dy: -2), xRadius: 3, yRadius: 3)
            path.lineWidth = 1
            NSColor.white.withAlphaComponent(0.45).setStroke()
            path.stroke()
        }

        if let rect = dragRect ?? state.selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemBlue.withAlphaComponent(0.08).setFill()
            rect.fill(using: .sourceOver)
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            NSColor.systemBlue.setStroke()
            border.stroke()
            drawBadge("\(Int(rect.width)) × \(Int(rect.height))",
                      centeredAt: CGPoint(x: rect.midX, y: rect.minY - 26 > bounds.minY ? rect.minY - 14 : rect.maxY + 14),
                      fontSize: 11)
        }

        if dragRect == nil, let focused = state.focused {
            let path = NSBezierPath(roundedRect: focused.insetBy(dx: -2, dy: -2), xRadius: 3, yRadius: 3)
            path.lineWidth = 2
            NSColor.systemYellow.setStroke()
            path.stroke()
        }

        if dragRect == nil, let cursor = state.cursor {
            drawCrosshair(at: cursor)
        }

        var badgeY = bounds.maxY - 80
        if let hint = state.hint, dragRect == nil {
            drawBadge(hint, centeredAt: CGPoint(x: bounds.midX, y: badgeY), fontSize: 13)
            badgeY -= 34
        }
        if let status = state.status {
            drawBadge(status, centeredAt: CGPoint(x: bounds.midX, y: badgeY), fontSize: 13)
        }
        formatSwitchRect = state.formatSwitch.map {
            drawBadge($0, centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 70), fontSize: 13)
        }
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: point.x - 12, y: point.y))
        path.line(to: CGPoint(x: point.x + 12, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 12))
        path.line(to: CGPoint(x: point.x, y: point.y + 12))
        path.appendOval(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        path.lineWidth = 3
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.stroke()
        path.lineWidth = 1.5
        NSColor.systemYellow.setStroke()
        path.stroke()
    }

    @discardableResult
    private func drawBadge(_ text: String, centeredAt center: CGPoint, fontSize: CGFloat) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let badge = CGRect(x: center.x - size.width / 2 - 10, y: center.y - size.height / 2 - 5,
                           width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + 10, y: badge.minY + 5), withAttributes: attributes)
        return badge
    }
}
