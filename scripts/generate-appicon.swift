#!/usr/bin/env swift
// Renders packaging/macos/AppIcon.png (1024 px), the AppIcon.iconset sizes and AppIcon.icns.
// Usage: swift scripts/generate-appicon.swift   (run from the project root)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("packaging/macos")

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // Squircle background with a blue → indigo gradient (Apple icon grid: 824 pt body inside 1024).
    let body = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.42, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.24, green: 0.16, blue: 0.62, alpha: 1)])!.draw(in: body, angle: -90)

    // Text lines; the middle one is "focused" (yellow), as in text mode.
    let lines: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (250, 640, 470, NSColor.white.withAlphaComponent(0.55)),
        (250, 540, 540, NSColor.systemYellow),
        (250, 440, 400, NSColor.white.withAlphaComponent(0.55)),
        (250, 340, 500, NSColor.white.withAlphaComponent(0.55)),
    ]
    for (x, y, w, color) in lines {
        color.setFill()
        NSBezierPath(roundedRect: r(x, y, w, 46), xRadius: 23 * s, yRadius: 23 * s).fill()
    }

    // Selection frame: white corner brackets around the text block.
    let frame = r(200, 280, 624, 470)
    let arm = 110 * s
    let bracket = NSBezierPath()
    bracket.lineWidth = 34 * s
    bracket.lineCapStyle = .round
    bracket.lineJoinStyle = .round
    for (cx, cy, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                             (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        bracket.move(to: CGPoint(x: cx, y: cy + dy * arm))
        bracket.line(to: CGPoint(x: cx, y: cy))
        bracket.line(to: CGPoint(x: cx + dx * arm, y: cy))
    }
    NSColor.white.setStroke()
    bracket.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
write(render(size: 1024), to: out.appendingPathComponent("AppIcon.png"))
for base in [16, 32, 128, 256, 512] {
    write(render(size: CGFloat(base)), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    write(render(size: CGFloat(base * 2)), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(out.path)/AppIcon.{png,icns}" : "iconutil failed")
