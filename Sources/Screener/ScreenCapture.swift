import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The selected display is no longer available."
        case .emptySelection: return "The selected area is empty."
        }
    }
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt once; afterwards the user must enable it in System Settings.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Captures `rect` (global AppKit coordinates, bottom-left origin) from `screen`, excluding Screener's own windows.
    static func capture(rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let screenFrame = screen.frame
        let local = CGRect(x: rect.minX - screenFrame.minX,
                           y: screenFrame.maxY - rect.maxY,
                           width: rect.width, height: rect.height).integral
        guard local.width >= 1, local.height >= 1 else { throw CaptureError.emptySelection }

        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else { throw CaptureError.displayNotFound }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = Int(local.width * scale)
        configuration.height = Int(local.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
