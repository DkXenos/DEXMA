import AppKit
import ScreenCaptureKit

/// Freezes a display: one ScreenCaptureKit screenshot at its native pixels with every DEXMA
/// window left out by the content filter (so nothing of DEXMA has to be hidden or wait to finish
/// closing first), plus the other apps' window frames for click-to-capture. Needs Screen
/// Recording. The work happens off the main thread.
enum ScreenFreezer {
    enum Failure: Error {
        case noDisplay
    }

    /// The display `screen` as it is right now.
    static func freeze(_ screen: NSScreen) async throws -> FrozenScreen {
        guard let displayID = screen.displayID else { throw Failure.noDisplay }
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        let colorSpace = screen.colorSpace?.cgColorSpace?.name
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.noDisplay }
        let mine = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int((size.width * scale).rounded())
        configuration.height = Int((size.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        if let colorSpace { configuration.colorSpaceName = colorSpace }
        // The picture and the window list at the same moment, as near as possible.
        async let image = SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let frames = content.windows.reduce(into: [CGWindowID: CGRect]()) { $0[$1.windowID] = $1.frame }
        let displayFrame = display.frame
        let windows = await Task.detached(priority: .userInitiated) {
            windowFrames(on: displayFrame, frames: frames)
        }.value
        return FrozenScreen(image: try await image, size: size, windows: windows)
    }

    /// Whether ScreenCaptureKit works right now. After Screen Recording is granted, macOS may
    /// only let it work once DEXMA has been reopened.
    static func isWorking() async -> Bool {
        (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil
    }

    /// Other apps' ordinary windows on the display (below the Dock's level: no menu bar, Dock or
    /// desktop), front to back (the window server's order), in the display's points.
    /// `frames`: ScreenCaptureKit's frame per window (global, top-left origin).
    private nonisolated static func windowFrames(on display: CGRect, frames: [CGWindowID: CGRect]) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { info -> CGRect? in
            guard let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, (0..<20).contains(layer),
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            guard let frame = frames[number] ?? bounds, frame.width >= 40, frame.height >= 40,
                  frame.intersects(display) else { return nil }
            return frame.offsetBy(dx: -display.minX, dy: -display.minY)
        }
    }
}
