import AppKit

struct CaptureRecord {
    let text: String
    let engine: String
    let date: Date
}

@MainActor
final class CaptureHistory {
    private(set) var items: [CaptureRecord] = []
    var limit: Int {
        didSet { trim() }
    }

    init(limit: Int) {
        self.limit = limit
    }

    func add(_ record: CaptureRecord) {
        items.removeAll { $0.text == record.text }
        items.insert(record, at: 0)
        trim()
    }

    func clear() { items.removeAll() }

    private func trim() {
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// A small HUD that fades out; shown next to the selection.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    static func show(_ message: String, detail: String? = nil, near rect: CGRect?, on screen: NSScreen?, duration: TimeInterval) {
        panel?.orderOut(nil)
        generation += 1
        let current = generation

        let title = NSTextField(labelWithString: message)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let stack = NSStackView(views: [title])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        if let detail {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 320
            stack.addArrangedSubview(label)
        }
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        let size = stack.fittingSize

        let target = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = target.visibleFrame
        var origin: CGPoint
        if let rect {
            origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 10)
            if origin.y < visible.minY { origin.y = rect.maxY + 10 }
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = effect
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard current == generation else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    if current == generation { panel.orderOut(nil) }
                }
            })
        }
    }
}
