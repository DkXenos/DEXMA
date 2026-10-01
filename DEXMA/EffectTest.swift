#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only: `DEXMA -effecttest <dir>` checks the liquid effect against what the window
/// server actually composited for the panel (an app may capture its own window without
/// Screen Recording permission), measures frame pacing with the effect on and off, and writes
/// posed frames as PNGs for a visual check. Prints `[effect] …` lines, then quits.
enum EffectTest {
    static func run(panel: NSPanel, controller: PanelController, session: ShellSession, dir: URL) {
        Task { @MainActor in
            // The Mac may be in use while this runs: another app taking focus must not close
            // the panel mid-test (focus handling itself is covered by -selftest).
            controller.closesOnFocusLoss = false
            session.terminalView.process.send(data: ArraySlice(Array("clear; seq 1 80; echo effect test\r".utf8)))
            try? await Task.sleep(for: .seconds(1.5))
            controller.open()
            await waitForRest(controller)

            snapshotFidelity(panel: panel, controller: controller, session: session, dir: dir)
            await restSwap("open", panel: panel, controller: controller, session: session, dir: dir)
            controller.close()
            await waitForRest(controller)
            await restSwap("closed", panel: panel, controller: controller, session: session, dir: dir)

            for intensity in [0.0, 1.0] {
                controller.effectIntensity = intensity
                await pacing(intensity: intensity, controller: controller)
            }
            await swapBack(panel: panel, controller: controller, dir: dir)
            await interactions(panel: panel, controller: controller, session: session)
            await poses(panel: panel, controller: controller, dir: dir)
            NSApp.terminate(nil)
        }
    }

    // MARK: Tests

    /// The production snapshot, composited over black like the live view, against the window.
    private static func snapshotFidelity(panel: NSPanel, controller: PanelController, session: ShellSession, dir: URL) {
        session.restartCaretBlink()  // Caret at full opacity, as snapshots draw it.
        guard let truth = windowImage(panel) else { return print("[effect] window capture failed") }
        let scale = panel.backingScaleFactor
        let frame = controller.geometry.terminalFrame
        let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                          width: frame.width * scale, height: frame.height * scale)
        var times: [Double] = []
        var snapshot: TerminalSnapshot?
        for _ in 0..<15 {
            let start = CACurrentMediaTime()
            snapshot = TerminalSnapshot.capture(session.terminalView)
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        guard let truthCrop = truth.cropping(to: crop), let snapshot,
              let composed = overBlack(snapshot.image) else { return }
        write(truthCrop, dir, "fidelity-truth")
        write(composed, dir, "fidelity-snapshot")
        print(String(format: "[effect] snapshot capture: first %.2f ms, median %.2f ms, caret %@",
                     times[0], times.sorted()[times.count / 2], snapshot.showsCaret ? "yes" : "no"))
        print("[effect] snapshot vs window: \(compare(composed, truthCrop))")
    }

    /// Live view vs motion layer with every effect at zero, at rest: must be identical.
    private static func restSwap(_ label: String, panel: NSPanel, controller: PanelController,
                                 session: ShellSession, dir: URL) async {
        session.restartCaretBlink()
        try? await Task.sleep(for: .milliseconds(30))
        guard let live = windowImage(panel) else { return }
        controller.debugBeginMotion()
        var samples: [String] = []
        for delay in [20, 40, 80, 150, 300] {
            try? await Task.sleep(for: .milliseconds(delay))
            if let image = windowImage(panel) { samples.append("\(compareCounts(image, live).differing)") }
        }
        print("[effect]   motion layer over time vs live (px): \(samples.joined(separator: " "))")
        guard let motion = windowImage(panel) else { return }
        controller.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(150))
        guard let back = windowImage(panel) else { return }
        write(live, dir, "rest-\(label)-live")
        write(motion, dir, "rest-\(label)-motion")
        print("[effect] at rest \(label), live vs motion layer: \(compare(motion, live))")
        print("[effect] at rest \(label), live vs live again:   \(compare(back, live))")
    }

    /// Frame pacing on the panel's display link through open/close cycles, plus the longest
    /// main-thread run-loop pass (which includes SwiftUI's render/commit) while animating.
    private static func pacing(intensity: Double, controller: PanelController) async {
        var stamps: [CFTimeInterval] = []
        var stepTimes: [Double] = []
        var busy: [Double] = []
        var passStart: CFTimeInterval = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { passStart = now } else if passStart > 0, controller.debugDriver.isAnimating {
                busy.append((now - passStart) * 1000)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        controller.debugDriver.debugFrameLog = { stamp, duration in
            stamps.append(stamp)
            stepTimes.append(duration * 1000)
        }
        var intervals: [Double] = []
        var lateAt: [String] = []
        var startDelays: [Double] = []
        for _ in 0..<3 {
            for open in [true, false] {
                stamps.removeAll()
                let requested = CACurrentMediaTime()
                if open { controller.open() } else { controller.close() }
                let callTime = (CACurrentMediaTime() - requested) * 1000
                await waitForRest(controller)
                if let first = stamps.first { startDelays.append((first - requested) * 1000) }
                let these = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
                for (i, interval) in these.enumerated() where interval > 12.5 {
                    lateAt.append(String(format: "%@ frame %d/%d: %.1f ms", open ? "open" : "close", i + 1, these.count, interval))
                }
                lateAt.append(String(format: "(%@ call %.2f ms)", open ? "open" : "close", callTime))
                intervals += these
            }
        }
        print("[effect]   intensity \(intensity): late frames: \(lateAt.joined(separator: ", ")); first frame after request: \(startDelays.map { String(format: "%.1f", $0) }.joined(separator: " ")) ms")
        controller.debugDriver.debugFrameLog = nil
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        let period = intervals.min() ?? 8.33
        let late = intervals.filter { $0 > period * 1.5 }.count
        print(String(format: "[effect] pacing, intensity %.0f: %d frames, period %.2f ms, %d late (>1.5×), worst interval %.2f ms; step max %.3f ms; run-loop pass p50 %.2f / p95 %.2f / max %.2f ms",
                     intensity, intervals.count + 6, period, late, intervals.max() ?? 0,
                     stepTimes.max() ?? 0, percentile(busy, 0.5), percentile(busy, 0.95), busy.max() ?? 0))
    }

    /// A real open: captures the window every frame from when the spring rests until a few
    /// frames after the live terminal is back, and compares each with the final frame.
    private static func swapBack(panel: NSPanel, controller: PanelController, dir: URL) async {
        controller.close()
        await waitForRest(controller)
        controller.open()
        var frames: [(active: Bool, image: CGImage)] = []
        var afterSwap = 0
        while afterSwap < 6, frames.count < 120 {
            try? await Task.sleep(for: .milliseconds(4))
            guard !controller.debugDriver.isSpringing else { continue }
            guard let image = windowImage(panel) else { break }
            let active = controller.effects.isActive
            frames.append((active, image))
            if !active { afterSwap += 1 }
        }
        guard let final = frames.last?.image else { return }
        var report: [String] = []
        for (index, frame) in frames.enumerated() {
            let diff = compareCounts(frame.image, final)
            report.append("\(frame.active ? "M" : "L")\(diff.differing)/\(diff.maxDiff)")
            if index == frames.count - 1 - 6 || index == frames.count - 6 {
                write(frame.image, dir, "swap-\(index)-\(frame.active ? "motion" : "live")")
            }
        }
        print("[effect] swap-back frames (M = motion layer, L = live; px differing from final / max diff): \(report.joined(separator: " "))")
    }

    /// Finger-driven swipes and interruptions: every one must end in a consistent state, with
    /// the live terminal back (open) or hidden (closed) and the motion layer gone.
    private static func interactions(panel: NSPanel, controller: PanelController, session: ShellSession) async {
        func report(_ label: String, expectOpen: Bool) {
            let ok = controller.state == (expectOpen ? .open : .closed)
                && controller.progress == (expectOpen ? 1 : 0)
                && !controller.effects.isActive
                && controller.backdrop?.isShowing != true
                && session.container.isHidden == !expectOpen
                && (!expectOpen || panel.firstResponder === session.terminalView)
            print("[effect] \(ok ? "OK  " : "FAIL") \(label): state=\(controller.state) progress=\(controller.progress) motion=\(controller.effects.isActive) glass=\(controller.backdrop?.isShowing == true) hidden=\(session.container.isHidden) key=\(panel.isKeyWindow)")
        }
        func swipe(to delta: CGFloat, steps: Int, release velocity: CGFloat) async {
            controller.beginInteraction()
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(8))
                controller.updateInteraction(delta: delta * CGFloat(i) / CGFloat(steps))
            }
            controller.endInteraction(velocity: velocity)
        }
        controller.close()
        await waitForRest(controller)
        await swipe(to: 0.7, steps: 30, release: 2.5)
        await waitForRest(controller)
        report("swipe open, released past the threshold", expectOpen: true)
        await swipe(to: -0.3, steps: 12, release: -0.2)
        await waitForRest(controller)
        report("short up-swipe, released before the threshold (snaps back open)", expectOpen: true)
        await swipe(to: -0.25, steps: 8, release: -4)
        await waitForRest(controller)
        report("quick flick up (velocity commits it)", expectOpen: false)
        controller.open()
        try? await Task.sleep(for: .milliseconds(90))
        controller.close()
        try? await Task.sleep(for: .milliseconds(60))
        controller.open()
        await waitForRest(controller)
        report("open → close → open, each mid-flight", expectOpen: true)
        controller.close()
        try? await Task.sleep(for: .milliseconds(80))
        await swipe(to: 0.4, steps: 10, release: 1.5)  // Grab the closing panel and pull it back.
        await waitForRest(controller)
        report("grabbed mid-close and pulled back open", expectOpen: true)
        controller.close()
        await waitForRest(controller)
        report("closed again", expectOpen: false)
        controller.open()
        await waitForRest(controller)
    }

    /// Frozen frames for a visual check of each effect.
    private static func poses(panel: NSPanel, controller: PanelController, dir: URL) async {
        controller.effectIntensity = 1
        controller.debugBeginMotion()
        let poses: [(String, CGFloat, MotionEffects.Frame)] = [
            ("anticipation", 0.03, .init(stretch: 0, bulge: 0.07, energy: 0.2)),
            ("opening-30", 0.3, .init(stretch: 0.06, bulge: 0, energy: 1)),
            ("opening-60", 0.6, .init(stretch: 0.05, bulge: 0, energy: 1)),
            ("opening-85", 0.85, .init(stretch: 0.03, bulge: 0, energy: 0.6)),
            ("landing-squash", 1.0, .init(stretch: -0.03, bulge: 0, energy: 0.1)),
            ("closing-96", 0.96, .init(stretch: 0.03, bulge: 0, energy: 1)),
            ("opening-15", 0.15, .init(stretch: 0.07, bulge: 0.02, energy: 1)),
        ]
        print("[effect] backdrop lens available: \(controller.backdrop?.isAvailable == true)")
        print("[effect] poses: active \(controller.effects.isActive), snapshot \(controller.effects.snapshot.map { "\($0.image.width)x\($0.image.height)" } ?? "nil")")
        for (name, progress, effect) in poses {
            controller.debugPose(progress: progress, effect: effect)
            try? await Task.sleep(for: .milliseconds(120))
            if let image = windowImage(panel) { write(image, dir, "pose-\(name)") }
        }
        controller.debugPose(progress: 1, effect: .init())
        controller.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Helpers

    private static func waitForRest(_ controller: PanelController) async {
        for _ in 0..<400 {
            try? await Task.sleep(for: .milliseconds(10))
            if !controller.debugDriver.isAnimating, !controller.effects.isActive { return }
        }
        print("[effect] timed out waiting for rest")
    }

    /// The panel as the window server composited it. Looked up at runtime: the API is
    /// deprecated since macOS 14 (fine for a debug check, not for shipping).
    static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // includingWindow = 1 << 3; boundsIgnoreFraming = 1 << 0, bestResolution = 1 << 3.
        return capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }

    private static func overBlack(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private static func compareCounts(_ a: CGImage, _ b: CGImage) -> (differing: Int, maxDiff: Int, box: String) {
        guard a.width == b.width, a.height == b.height else { return (-1, -1, "size mismatch") }
        let pa = rgba(a), pb = rgba(b)
        var differing = 0, maxDiff = 0
        var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            maxDiff = max(maxDiff, d)
            if d > 2 {
                differing += 1
                let x = (i / 4) % a.width, y = (i / 4) / a.width
                box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
            }
        }
        return (differing, maxDiff, differing == 0 ? "" : "x \(box.minX)…\(box.maxX) y \(box.minY)…\(box.maxY)")
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        let r = compareCounts(a, b)
        return "\(r.differing) px differ by >2/255 \(r.box), max channel diff \(r.maxDiff) (\(a.width)×\(a.height))"
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    private static func write(_ image: CGImage, _ dir: URL, _ name: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
