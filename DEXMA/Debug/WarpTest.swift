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
    static func keepCapturing(notch: NotchViewModel, seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let end = CACurrentMediaTime() + seconds
            while CACurrentMediaTime() < end {
                notch.bender?.debugKeepCapturing()
                try? await Task.sleep(for: .milliseconds(500))
            }
            let stats = notch.bender?.debugCapture.statistics()
            print("[warp] idle capture: \(stats?.frames ?? 0) frames in \(seconds) s")
            NSApp.terminate(nil)
        }
    }

    static func run(panel: NSPanel, notch: NotchViewModel, dir: URL) {
        let report = Report(dir: dir)
        Task { @MainActor in
            notch.closesOnFocusLoss = false  // The Mac may be in use while this runs.
            guard CGPreflightScreenCaptureAccess(), let bender = notch.bender else {
                report.line("Screen Recording is not granted to DEXMA: nothing measured.")
                NSApp.terminate(nil)
                return
            }
            notch.effectIntensity = 1
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
            notch.open()
            var warpAt: CFTimeInterval?
            for _ in 0..<200 {
                try? await Task.sleep(for: .milliseconds(4))
                if bender.debugWarpShowing { warpAt = CACurrentMediaTime(); break }
                if !notch.effects.isActive, !notch.debugDriver.isAnimating { break }
            }
            report.line("open from cold: warp drawn after " + (warpAt.map { String(format: "%.0f ms", ($0 - opened) * 1000) } ?? "never (animation over first)"))
            _ = await notch.waitForRest()

            // 3. Frame pacing over open/close cycles with the warp on (stream already running).
            await pacing(notch: notch, capture: capture, report: report)

            bender.debugPosing = true
            // 4. Colour match: warp layer covering everything with zero bend vs no warp layer.
            notch.close()
            _ = await notch.waitForRest()
            if let plain = await DebugImages.screen(around: panel) {
                bender.debugFullCoverage = true
                notch.debugBeginMotion()
                notch.debugPose(progress: 0, effect: .init(stretch: 0, bulge: 0, energy: 0))
                try? await Task.sleep(for: .milliseconds(200))
                if let covered = await DebugImages.screen(around: panel) {
                    report.line("colour match (warp layer, zero bend, vs real screen): \(compare(covered, plain))")
                    DebugImages.write(plain, dir, "screen-plain")
                    DebugImages.write(covered, dir, "screen-zero-bend")
                }
                bender.debugFullCoverage = false
                notch.debugEndMotion()
            }

            // 5. Posed warps, captured from the real screen for a visual check.
            notch.debugBeginMotion()
            for (name, progress, energy, stretch) in [("opening-35", 0.35, 1.0, 0.05), ("opening-70", 0.7, 0.8, 0.04),
                                                      ("anticipation", 0.03, 0.0, 0.0)] as [(String, CGFloat, CGFloat, CGFloat)] {
                notch.debugPose(progress: progress,
                                effect: .init(stretch: stretch, bulge: name == "anticipation" ? 0.07 : 0, energy: energy))
                try? await Task.sleep(for: .milliseconds(150))
                if let image = await DebugImages.screen(around: panel) { DebugImages.write(image, dir, "warp-\(name)") }
            }
            notch.debugPose(progress: 0, effect: .init())
            notch.debugEndMotion()
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

    private static func pacing(notch: NotchViewModel, capture: ScreenCapture, report: Report) async {
        let probe = FramePacingProbe(driver: notch.debugDriver)
        var intervals: [Double] = []
        let before = capture.statistics()
        for _ in 0..<3 {
            for open in [true, false] {
                probe.startSeries()
                if open { notch.open() } else { notch.close() }
                _ = await notch.waitForRest()
                intervals += zip(probe.stamps.dropFirst(), probe.stamps).map { ($0 - $1) * 1000 }
            }
        }
        probe.stop()
        let after = capture.statistics()
        let late = intervals.filter { $0 > 12.5 }.count
        let busy = probe.passes
        report.line(String(format: "pacing with warp: %d frames, %d over 12.5 ms, worst %.2f ms; main-thread pass p50 %.2f / p95 %.2f / max %.2f ms; capture frames %d, longest capture gap %.1f ms",
                           intervals.count, late, intervals.max() ?? 0, FramePacingProbe.percentile(busy, 0.5),
                           FramePacingProbe.percentile(busy, 0.95), busy.max() ?? 0,
                           after.frames - before.frames, after.longestGap * 1000))
    }

    /// Colour only: the screen captures are opaque.
    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        guard let r = DebugImages.difference(a, b, channels: 3) else { return "size mismatch" }
        return "\(r.differing) px differ by >2/255, max channel diff \(r.maxDiff)"
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
