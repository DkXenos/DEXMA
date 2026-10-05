#if DEBUG
import AppKit
import ScreenCaptureKit

/// Debug-only: `DEXMA -spotlightmeasure <dir>` pictures the real Spotlight (macOS 26) so the
/// floating glass window can be measured against it. DEXMA presses nothing itself (a Debug build
/// usually lacks Accessibility): something else opens Spotlight (⌘Space) and types a query; this
/// waits for Spotlight's window, saves a crop around it (`spotlight-empty.png`) and writes
/// `<dir>/empty-ready`, so the typing only starts once Spotlight is really up; then waits for the
/// window to grow with results and saves `spotlight-results.png`. Needs DEXMA's Screen Recording
/// grant: launch with `open`. Prints `[spotlight] …` lines (window frames in points, top-left
/// origin), then quits.
enum SpotlightMeasure {
    static func run(dir: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let first = await waitForWindows(seconds: 25, where: { _ in true }) else {
                print("[spotlight] no Spotlight window appeared")
                NSApp.terminate(nil)
                return
            }
            try? await Task.sleep(for: .milliseconds(700))  // Its appear animation has settled.
            let empty = frames()
            for frame in empty { print("[spotlight] empty: window \(frame)") }
            await save(around: empty, dir: dir, name: "spotlight-empty")
            FileManager.default.createFile(atPath: dir.appendingPathComponent("empty-ready").path, contents: nil)
            let height = first.map(\.height).max() ?? 0
            if await waitForWindows(seconds: 25, where: { $0.map(\.height).max() ?? 0 > height + 40 }) != nil {
                try? await Task.sleep(for: .milliseconds(1200))
                let results = frames()
                for frame in results { print("[spotlight] results: window \(frame)") }
                await save(around: results, dir: dir, name: "spotlight-results")
            } else {
                print("[spotlight] the window never grew with results")
            }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("done").path, contents: nil)
            NSApp.terminate(nil)
        }
    }

    private static func waitForWindows(seconds: Double, where condition: ([CGRect]) -> Bool) async -> [CGRect]? {
        let end = CACurrentMediaTime() + seconds
        while CACurrentMediaTime() < end {
            let found = frames()
            if !found.isEmpty, condition(found) { return found }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Spotlight's on-screen windows (global points, top-left origin), big enough to be its UI.
    private static func frames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Spotlight" }.compactMap { info in
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return rect.width > 20 && rect.height > 20 ? rect : nil
        }
    }

    /// A crop of the display around `windows`, 24 pt of margin, native pixels.
    private static func save(around windows: [CGRect], dir: URL, name: String) async {
        let union = windows.reduce(CGRect.null) { $0.union($1) }
        let primaryHeight = NSScreen.screens[0].frame.height
        // Global top-left points → the AppKit screen it's on.
        let appKitCenter = CGPoint(x: union.midX, y: primaryHeight - union.midY)
        guard !union.isNull, let screen = NSScreen.screens.first(where: { NSPointInRect(appKitCenter, $0.frame) }),
              let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            print("[spotlight] \(name): nothing to capture (Screen Recording?)")
            return
        }
        let displayTop = primaryHeight - screen.frame.maxY
        let local = union.offsetBy(dx: -screen.frame.minX, dy: -displayTop).insetBy(dx: -24, dy: -24)
            .intersection(CGRect(origin: .zero, size: screen.frame.size))
        print("[spotlight] screen \(screen.frame) visible \(screen.visibleFrame) scale \(screen.backingScaleFactor)")
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = Int(local.width * screen.backingScaleFactor)
        configuration.height = Int(local.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            print("[spotlight] \(name): capture failed")
            return
        }
        DebugImages.write(image, dir, name)
        print("[spotlight] \(name): saved, crop origin (display points) \(local.origin), size \(local.size)")
    }
}
#endif
