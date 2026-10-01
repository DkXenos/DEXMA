#if DEBUG
import AppKit
import ScreenCaptureKit

/// Debug-only: `DEXMA -warptest <dir>` measures the Screen Recording warp. Launch it with
/// `open -n -W DEXMA.app --args -warptest <dir>` so DEXMA's own Screen Recording permission
/// applies (a shell launch inherits the terminal's). Writes `<dir>/report.txt` and PNGs of the
/// real screen around the notch (captured with ScreenCaptureKit, DEXMA included), then quits.
enum WarpTest {
    /// `-captureidle <seconds>`: capture running with nothing moving, for measuring its cost
    /// from outside (top). Then quits.
    static func keepCapturing(controller: PanelController, seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let end = CACurrentMediaTime() + seconds
            while CACurrentMediaTime() < end {
                controller.bender?.debugKeepCapturing()
                try? await Task.sleep(for: .milliseconds(500))
            }
            let stats = controller.bender?.debugCapture.statistics()
            print("[warp] idle capture: \(stats?.frames ?? 0) frames in \(seconds) s")
            NSApp.terminate(nil)
        }
    }

    static func run(panel: NSPanel, controller: PanelController, dir: URL) {
        let report = Report(dir: dir)
        Task { @MainActor in
            controller.closesOnFocusLoss = false  // The Mac may be in use while this runs.
            guard CGPreflightScreenCaptureAccess(), let bender = controller.bender else {
                report.line("Screen Recording is not granted to DEXMA: nothing measured.")
                NSApp.terminate(nil)
                return
            }
            controller.effectIntensity = 1
            bender.isWarpEnabled = true
            let capture = bender.debugCapture
            try? await Task.sleep(for: .seconds(1))

            // 1. Stream start → first frame, cold (first ever) then warm (stopped and restarted).
            for run in 1...4 {
                capture.stop()
                try? await Task.sleep(for: .milliseconds(run == 1 ? 0 : 800))
                bender.prepare()
                let latency = await firstFrameLatency(capture)
                report.line(String(format: "start → first frame, run %d: %@", run,
                                   latency.map { String(format: "%.0f ms", $0 * 1000) } ?? "no frame in 3 s"))
            }

            // 2. Hotkey open with the stream stopped: how far into the animation the warp starts.
            capture.stop()
            try? await Task.sleep(for: .milliseconds(800))
            let opened = CACurrentMediaTime()
            controller.open()
            var warpAt: CFTimeInterval?
            for _ in 0..<200 {
                try? await Task.sleep(for: .milliseconds(4))
                if bender.debugWarpShowing { warpAt = CACurrentMediaTime(); break }
                if !controller.effects.isActive, !controller.debugDriver.isAnimating { break }
            }
            report.line("open from cold: warp drawn after " + (warpAt.map { String(format: "%.0f ms", ($0 - opened) * 1000) } ?? "never (animation over first)"))
            await waitForRest(controller)

            // 3. Frame pacing over open/close cycles with the warp on (stream already running).
            await pacing(controller: controller, capture: capture, report: report)

            bender.debugPosing = true
            // 4. Colour match: warp layer covering everything with zero bend vs no warp layer.
            controller.close()
            await waitForRest(controller)
            if let plain = await screenImage(around: panel) {
                bender.debugFullCoverage = true
                controller.debugBeginMotion()
                controller.debugPose(progress: 0, effect: .init(stretch: 0, bulge: 0, energy: 0))
                try? await Task.sleep(for: .milliseconds(200))
                if let covered = await screenImage(around: panel) {
                    report.line("colour match (warp layer, zero bend, vs real screen): \(compare(covered, plain))")
                    write(plain, dir, "screen-plain")
                    write(covered, dir, "screen-zero-bend")
                }
                bender.debugFullCoverage = false
                controller.debugEndMotion()
            }

            // 5. Posed warps, captured from the real screen for a visual check.
            controller.debugBeginMotion()
            for (name, progress, energy, stretch) in [("opening-35", 0.35, 1.0, 0.05), ("opening-70", 0.7, 0.8, 0.04),
                                                      ("anticipation", 0.03, 0.0, 0.0)] as [(String, CGFloat, CGFloat, CGFloat)] {
                controller.debugPose(progress: progress,
                                     effect: .init(stretch: stretch, bulge: name == "anticipation" ? 0.07 : 0, energy: energy))
                try? await Task.sleep(for: .milliseconds(150))
                if let image = await screenImage(around: panel) { write(image, dir, "warp-\(name)") }
            }
            controller.debugPose(progress: 0, effect: .init())
            controller.debugEndMotion()
            report.line("done")
            NSApp.terminate(nil)
        }
    }

    private static func firstFrameLatency(_ capture: ScreenCapture) async -> CFTimeInterval? {
        for _ in 0..<750 {
            try? await Task.sleep(for: .milliseconds(4))
            if let first = capture.statistics().firstFrame { return first - capture.requestTime }
        }
        return nil
    }

    private static func pacing(controller: PanelController, capture: ScreenCapture, report: Report) async {
        var stamps: [CFTimeInterval] = []
        var busy: [Double] = []
        var passStart: CFTimeInterval = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { passStart = now } else if passStart > 0, controller.debugDriver.isAnimating {
                busy.append((now - passStart) * 1000)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        controller.debugDriver.debugFrameLog = { stamp, _ in stamps.append(stamp) }
        var intervals: [Double] = []
        let before = capture.statistics()
        for _ in 0..<3 {
            for open in [true, false] {
                stamps.removeAll()
                if open { controller.open() } else { controller.close() }
                await waitForRest(controller)
                intervals += zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
            }
        }
        controller.debugDriver.debugFrameLog = nil
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        let after = capture.statistics()
        let late = intervals.filter { $0 > 12.5 }.count
        let sorted = busy.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        report.line(String(format: "pacing with warp: %d frames, %d over 12.5 ms, worst %.2f ms; main-thread pass p50 %.2f / p95 %.2f / max %.2f ms; capture frames %d, longest capture gap %.1f ms",
                           intervals.count, late, intervals.max() ?? 0, pct(0.5), pct(0.95), sorted.last ?? 0,
                           after.frames - before.frames, after.longestGap * 1000))
    }

    private static func waitForRest(_ controller: PanelController) async {
        for _ in 0..<400 {
            try? await Task.sleep(for: .milliseconds(10))
            if !controller.debugDriver.isAnimating, !controller.effects.isActive { return }
        }
    }

    /// The real screen (DEXMA included) around the panel.
    private static func screenImage(around panel: NSPanel) async -> CGImage? {
        guard let screen = panel.screen, let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let rect = panel.frame
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                          width: rect.width, height: rect.height)
        configuration.width = Int(rect.width * screen.backingScaleFactor)
        configuration.height = Int(rect.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        guard a.width == b.width, a.height == b.height else { return "size mismatch" }
        func rgba(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return data
        }
        let pa = rgba(a), pb = rgba(b)
        var differing = 0, maxDiff = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<3 { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            if d > 2 { differing += 1 }
            maxDiff = max(maxDiff, d)
        }
        return "\(differing) px differ by >2/255, max channel diff \(maxDiff)"
    }

    private static func write(_ image: CGImage, _ dir: URL, _ name: String) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Lines go to stdout and `<dir>/report.txt` (stdout is lost when launched with `open`).
    final class Report {
        private let url: URL
        init(dir: URL) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("report.txt")
            try? Data().write(to: url)
        }
        func line(_ text: String) {
            print("[warp] \(text)")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data((text + "\n").utf8))
                try? handle.close()
            }
        }
    }
}
#endif
