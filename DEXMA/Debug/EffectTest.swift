#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only: `DEXMA -effecttest <dir>` checks the liquid effect against what the window
/// server actually composited for the panel (an app may capture its own window without
/// Screen Recording permission), measures frame pacing with the effect on and off, and writes
/// posed frames as PNGs for a visual check. Prints `[effect] …` lines, then quits.
enum EffectTest {
    static func run(panel: NSPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        Task { @MainActor in
            // The Mac may be in use while this runs: another app taking focus must not close
            // the panel mid-test (focus handling itself is covered by -selftest).
            notch.closesOnFocusLoss = false
            session.terminalView.process.send(data: ArraySlice(Array("clear; seq 1 80; echo effect test\r".utf8)))
            try? await Task.sleep(for: .seconds(1.5))
            notch.open()
            await waitForRest(notch)

            snapshotFidelity(panel: panel, notch: notch, session: session, dir: dir)
            await restSwap("open", panel: panel, notch: notch, session: session, dir: dir)
            notch.close()
            await waitForRest(notch)
            await restSwap("closed", panel: panel, notch: notch, session: session, dir: dir)

            for intensity in [0.0, 1.0] {
                notch.effectIntensity = intensity
                await pacing(intensity: intensity, notch: notch)
            }
            await swapBack(panel: panel, notch: notch, dir: dir)
            await interactions(panel: panel, notch: notch, session: session)
            await poses(panel: panel, notch: notch, dir: dir)
            NSApp.terminate(nil)
        }
    }

    // MARK: Tests

    /// The production snapshot, composited over black like the live view, against the window.
    private static func snapshotFidelity(panel: NSPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        session.restartCaretBlink()  // Caret at full opacity, as snapshots draw it.
        guard let truth = DebugImages.window(panel) else { return print("[effect] window capture failed") }
        let scale = panel.backingScaleFactor
        let frame = notch.geometry.terminalFrame
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
              let composed = DebugImages.overBlack(snapshot.image) else { return }
        DebugImages.write(truthCrop, dir, "fidelity-truth")
        DebugImages.write(composed, dir, "fidelity-snapshot")
        print(String(format: "[effect] snapshot capture: first %.2f ms, median %.2f ms, caret %@",
                     times[0], times.sorted()[times.count / 2], snapshot.showsCaret ? "yes" : "no"))
        print("[effect] snapshot vs window: \(compare(composed, truthCrop))")
    }

    /// Live view vs motion layer with every effect at zero, at rest: must be identical.
    private static func restSwap(_ label: String, panel: NSPanel, notch: NotchViewModel,
                                 session: ShellSession, dir: URL) async {
        session.restartCaretBlink()
        try? await Task.sleep(for: .milliseconds(30))
        guard let live = DebugImages.window(panel) else { return }
        notch.debugBeginMotion()
        var samples: [String] = []
        for delay in [20, 40, 80, 150, 300] {
            try? await Task.sleep(for: .milliseconds(delay))
            if let image = DebugImages.window(panel) { samples.append("\(differenceCounts(image, live).differing)") }
        }
        print("[effect]   motion layer over time vs live (px): \(samples.joined(separator: " "))")
        guard let motion = DebugImages.window(panel) else { return }
        notch.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(150))
        guard let back = DebugImages.window(panel) else { return }
        DebugImages.write(live, dir, "rest-\(label)-live")
        DebugImages.write(motion, dir, "rest-\(label)-motion")
        print("[effect] at rest \(label), live vs motion layer: \(compare(motion, live))")
        print("[effect] at rest \(label), live vs live again:   \(compare(back, live))")
    }

    /// Frame pacing on the panel's display link through open/close cycles, plus the longest
    /// main-thread run-loop pass (which includes SwiftUI's render/commit) while animating.
    private static func pacing(intensity: Double, notch: NotchViewModel) async {
        let probe = FramePacingProbe(driver: notch.debugDriver)
        var intervals: [Double] = []
        var lateAt: [String] = []
        var startDelays: [Double] = []
        for _ in 0..<3 {
            for open in [true, false] {
                probe.startSeries()
                let requested = CACurrentMediaTime()
                if open { notch.open() } else { notch.close() }
                let callTime = (CACurrentMediaTime() - requested) * 1000
                await waitForRest(notch)
                let stamps = probe.stamps
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
        probe.stop()
        let busy = probe.passes
        let period = intervals.min() ?? 8.33
        let late = intervals.filter { $0 > period * 1.5 }.count
        print(String(format: "[effect] pacing, intensity %.0f: %d frames, period %.2f ms, %d late (>1.5×), worst interval %.2f ms; step max %.3f ms; run-loop pass p50 %.2f / p95 %.2f / max %.2f ms",
                     intensity, intervals.count + 6, period, late, intervals.max() ?? 0,
                     probe.stepTimes.max() ?? 0, FramePacingProbe.percentile(busy, 0.5),
                     FramePacingProbe.percentile(busy, 0.95), busy.max() ?? 0))
    }

    /// A real open: captures the window every frame from when the spring rests until a few
    /// frames after the live terminal is back, and compares each with the final frame.
    private static func swapBack(panel: NSPanel, notch: NotchViewModel, dir: URL) async {
        notch.close()
        await waitForRest(notch)
        notch.open()
        var frames: [(active: Bool, image: CGImage)] = []
        var afterSwap = 0
        while afterSwap < 6, frames.count < 120 {
            try? await Task.sleep(for: .milliseconds(4))
            guard !notch.debugDriver.isSpringing else { continue }
            guard let image = DebugImages.window(panel) else { break }
            let active = notch.effects.isActive
            frames.append((active, image))
            if !active { afterSwap += 1 }
        }
        guard let final = frames.last?.image else { return }
        var report: [String] = []
        for (index, frame) in frames.enumerated() {
            let diff = differenceCounts(frame.image, final)
            report.append("\(frame.active ? "M" : "L")\(diff.differing)/\(diff.maxDiff)")
            if index == frames.count - 1 - 6 || index == frames.count - 6 {
                DebugImages.write(frame.image, dir, "swap-\(index)-\(frame.active ? "motion" : "live")")
            }
        }
        print("[effect] swap-back frames (M = motion layer, L = live; px differing from final / max diff): \(report.joined(separator: " "))")
    }

    /// Finger-driven swipes and interruptions: every one must end in a consistent state, with
    /// the live terminal back (open) or hidden (closed) and the motion layer gone.
    private static func interactions(panel: NSPanel, notch: NotchViewModel, session: ShellSession) async {
        func report(_ label: String, expectOpen: Bool) {
            let ok = notch.state == (expectOpen ? .open : .closed)
                && notch.progress == (expectOpen ? 1 : 0)
                && !notch.effects.isActive
                && notch.bender?.debugGlassShowing != true
                && notch.bender?.debugWarpShowing != true
                && session.container.isHidden == !expectOpen
                && (!expectOpen || panel.firstResponder === session.terminalView)
            print("[effect] \(ok ? "OK  " : "FAIL") \(label): state=\(notch.state) progress=\(notch.progress) motion=\(notch.effects.isActive) glass=\(notch.bender?.debugGlassShowing == true) warp=\(notch.bender?.debugWarpShowing == true) hidden=\(session.container.isHidden) key=\(panel.isKeyWindow)")
        }
        func swipe(to delta: CGFloat, steps: Int, release velocity: CGFloat) async {
            notch.beginInteraction()
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(8))
                notch.updateInteraction(delta: delta * CGFloat(i) / CGFloat(steps))
            }
            notch.endInteraction(velocity: velocity)
        }
        notch.close()
        await waitForRest(notch)
        await swipe(to: 0.7, steps: 30, release: 2.5)
        await waitForRest(notch)
        report("swipe open, released past the threshold", expectOpen: true)
        await swipe(to: -0.3, steps: 12, release: -0.2)
        await waitForRest(notch)
        report("short up-swipe, released before the threshold (snaps back open)", expectOpen: true)
        await swipe(to: -0.25, steps: 8, release: -4)
        await waitForRest(notch)
        report("quick flick up (velocity commits it)", expectOpen: false)
        notch.open()
        try? await Task.sleep(for: .milliseconds(90))
        notch.close()
        try? await Task.sleep(for: .milliseconds(60))
        notch.open()
        await waitForRest(notch)
        report("open → close → open, each mid-flight", expectOpen: true)
        notch.close()
        try? await Task.sleep(for: .milliseconds(80))
        await swipe(to: 0.4, steps: 10, release: 1.5)  // Grab the closing panel and pull it back.
        await waitForRest(notch)
        report("grabbed mid-close and pulled back open", expectOpen: true)
        notch.close()
        await waitForRest(notch)
        report("closed again", expectOpen: false)
        notch.open()
        await waitForRest(notch)
    }

    /// Frozen frames for a visual check of each effect.
    private static func poses(panel: NSPanel, notch: NotchViewModel, dir: URL) async {
        notch.effectIntensity = 1
        notch.debugBeginMotion()
        let poses: [(String, CGFloat, MotionEffects.Frame)] = [
            ("anticipation", 0.03, .init(stretch: 0, bulge: 0.07, energy: 0.2)),
            ("opening-30", 0.3, .init(stretch: 0.06, bulge: 0, energy: 1)),
            ("opening-60", 0.6, .init(stretch: 0.05, bulge: 0, energy: 1)),
            ("opening-85", 0.85, .init(stretch: 0.03, bulge: 0, energy: 0.6)),
            ("landing-squash", 1.0, .init(stretch: -0.03, bulge: 0, energy: 0.1)),
            ("closing-96", 0.96, .init(stretch: 0.03, bulge: 0, energy: 1)),
            ("opening-15", 0.15, .init(stretch: 0.07, bulge: 0.02, energy: 1)),
        ]
        print("[effect] screen recording permitted: \(notch.bender?.debugPermitted == true)")
        print("[effect] poses: active \(notch.effects.isActive), snapshot \(notch.effects.snapshot.map { "\($0.image.width)x\($0.image.height)" } ?? "nil")")
        for (name, progress, effect) in poses {
            notch.debugPose(progress: progress, effect: effect)
            try? await Task.sleep(for: .milliseconds(120))
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "pose-\(name)") }
        }
        notch.debugPose(progress: 1, effect: .init())
        notch.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Helpers

    private static func waitForRest(_ notch: NotchViewModel) async {
        if await notch.waitForRest() { return }
        let d = notch.debugDriver
        print("[effect] timed out waiting for rest: animating=\(d.isAnimating) springing=\(d.isSpringing) held=\(d.isHeld) progress=\(notch.progress) state=\(notch.state) motion=\(notch.effects.isActive) frame=\(notch.effects.frame) screenVelocity=\(d.screenVelocity)")
    }

    /// Compared in all four channels (alpha too: the panel is transparent around the shape).
    private static func differenceCounts(_ a: CGImage, _ b: CGImage) -> (differing: Int, maxDiff: Int, box: String) {
        DebugImages.difference(a, b, channels: 4) ?? (-1, -1, "size mismatch")
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        let r = differenceCounts(a, b)
        return "\(r.differing) px differ by >2/255 \(r.box), max channel diff \(r.maxDiff) (\(a.width)×\(a.height))"
    }
}
#endif
