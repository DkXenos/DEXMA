#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only: `DEXMA -hovertest <dir>` checks the band controls' liquid glass. Hover is driven
/// through the lens (`ControlLens.hover(at:)`, what the control's `onContinuousHover` calls:
/// SwiftUI's hover tracking follows the real cursor, which this doesn't move); presses and
/// clicks are synthetic mouse events sent to the panel. It checks the lens's breath and rest,
/// that the warp stays within the control plus its margin, the exit back to exactly the plain
/// control, the press squash, the indicator's droplet stretch, intensity Off, Reduce Motion,
/// and frame pacing / main-thread time while the pointer glides and the terminal takes typing.
/// Prints `[hover] …` lines and PNGs, then quits.
enum HoverTest {
    static func run(panel: NotchPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false  // The Mac may be in use while this runs.
            notch.effectIntensity = 1
            session.terminalView.process.send(data: ArraySlice(Array("clear; echo hover test\r".utf8)))
            try? await Task.sleep(for: .seconds(1))
            notch.open()
            _ = await notch.waitForRest()
            try? await Task.sleep(for: .milliseconds(300))
            let geometry = notch.geometry
            let segment = CGSize(width: TabBand.labelledWidth, height: TabBand.segmentHeight)
            let tabs = geometry.tabBandFrame
            // The Search segment (the second), in panel coordinates (top-left origin).
            let search = CGRect(x: tabs.minX + segment.width + TabBand.spacing,
                                y: tabs.midY - segment.height / 2, width: segment.width, height: segment.height)
            let lens = notch.band.lens(for: "tab.\(PanelTab.search)")
            let allowed = search.insetBy(dx: -ControlLensEffect.margin, dy: -ControlLensEffect.margin)
            // Unfocused, the terminal's caret stops blinking, so only the warp changes pixels.
            panel.makeFirstResponder(nil)
            moveOut(panel)
            try? await Task.sleep(for: .milliseconds(300))
            guard let base = DebugImages.window(panel) else { return print("[hover] window capture failed") }
            DebugImages.write(base, dir, "base")

            // The shader switching on (and off) is invisible by itself: at (nearly) zero
            // strength, a hovered control is pixel-identical to the plain one.
            let full = notch.band.tuning
            var faint = full.scaled(by: 0)
            faint.controlLens = 1e-6
            notch.band.tuning = faint
            lens.hover(at: CGPoint(x: 20, y: search.height / 2))
            try? await Task.sleep(for: .milliseconds(500))
            if let attached = DebugImages.window(panel) {
                print("[hover] shader attached at ~zero vs plain (no tick on enter/exit): \(compare(attached, base)); active=\(lens.isActive)")
            }
            lens.hover(at: nil)
            try? await Task.sleep(for: .milliseconds(400))
            notch.band.tuning = full

            // Enter: the breath, then the resting lens.
            lens.hover(at: CGPoint(x: 20, y: search.height / 2))
            try? await Task.sleep(for: .milliseconds(30))
            report("pointer over Search → lens on", ok: lens.isActive, lens)
            try? await Task.sleep(for: .milliseconds(140))
            let breath = DebugImages.window(panel)
            report("breath (~0.17 s)", ok: lens.frame.strength > 0.8, lens)
            try? await Task.sleep(for: .milliseconds(500))
            let resting = DebugImages.window(panel)
            report("resting lens", ok: lens.isActive
                   && abs(lens.frame.strength - lens.tuning.controlRest) < 0.001, lens)
            for (name, image) in [("breath", breath), ("rest", resting)] {
                guard let image else { continue }
                DebugImages.write(image, dir, "hover-\(name)")
                print("[hover] \(name) vs no hover: \(confinement(image, base, allowed: allowed, panel: panel, geometry: geometry))")
            }

            // Exit: back to exactly the plain control.
            lens.hover(at: nil)
            try? await Task.sleep(for: .milliseconds(600))
            report("pointer left → shader detached, all zero", ok: !lens.isActive && lens.frame == ControlLens.Frame(), lens)
            if let after = DebugImages.window(panel) {
                print("[hover] after exit vs before hover: \(compare(after, base))")
            }

            // Glide across the control while the terminal takes typing.
            panel.makeFirstResponder(session.terminalView)
            await glide(panel: panel, notch: notch, session: session, over: search, lens: lens)
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "hover-glide-end") }
            lens.hover(at: nil)
            try? await Task.sleep(for: .milliseconds(600))

            // Press: squash, then the click (tick + Search tab), the indicator's droplet slide.
            lens.hover(at: CGPoint(x: search.width / 2, y: search.height / 2))
            try? await Task.sleep(for: .milliseconds(400))
            click(panel, at: CGPoint(x: search.midX, y: search.midY), down: true)
            try? await Task.sleep(for: .milliseconds(90))
            let squash = lens.frame.pressScale(lens.tuning)
            report(String(format: "pressed: squash %.3f × %.3f", squash.width, squash.height),
                   ok: squash.height < 0.95, lens)
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "press") }
            var stretches: [CGFloat] = []
            click(panel, at: CGPoint(x: search.midX, y: search.midY), down: false)
            for i in 0..<70 {
                try? await Task.sleep(for: .milliseconds(10))
                stretches.append(notch.band.indicator.stretch)
                if i == 8, let image = DebugImages.window(panel) { DebugImages.write(image, dir, "indicator-sliding") }
            }
            try? await Task.sleep(for: .milliseconds(500))
            let indicator = notch.band.indicator
            report(String(format: "click → Search; indicator stretch max %.3f, min %.3f; at rest %@",
                          stretches.max() ?? 0, stretches.min() ?? 0, "\(indicator)"),
                   ok: notch.tab == .search && (stretches.max() ?? 0) > 0.03
                   && indicator == BandMotion.Indicator() && notch.tabProgress == 1, lens)
            lens.hover(at: nil)
            try? await Task.sleep(for: .milliseconds(600))
            report("after the click, at rest", ok: !lens.isActive, lens)

            // Off: only the plain fill.
            notch.select(.terminal)
            try? await Task.sleep(for: .seconds(1))
            notch.effectIntensity = 0
            panel.makeFirstResponder(nil)
            try? await Task.sleep(for: .milliseconds(300))
            let offBase = DebugImages.window(panel)
            lens.hover(at: CGPoint(x: search.width / 2, y: search.height / 2))
            try? await Task.sleep(for: .milliseconds(300))
            report("intensity Off → no lens", ok: !lens.isActive, lens)
            if let off = DebugImages.window(panel), let offBase {
                print("[hover] Off, hovered vs not: \(compare(off, offBase))")
            }
            lens.hover(at: nil)
            notch.effectIntensity = 1

            // Reduce Motion: instant indicator, no lens, no squash.
            notch.band.reduceMotion = { true }
            notch.select(.search)
            report("Reduce Motion → indicator jumps", ok: notch.band.indicator == BandMotion.Indicator() && notch.tabProgress == 1, lens)
            lens.hover(at: CGPoint(x: search.width / 2, y: search.height / 2))
            try? await Task.sleep(for: .milliseconds(200))
            click(panel, at: CGPoint(x: search.midX, y: search.midY), down: true)
            try? await Task.sleep(for: .milliseconds(60))
            report("Reduce Motion → no lens, no squash", ok: !lens.isActive && lens.frame.press == 0, lens)
            click(panel, at: CGPoint(x: search.midX, y: search.midY), down: false)
            lens.hover(at: nil)
            notch.band.reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
            notch.select(.terminal)
            try? await Task.sleep(for: .seconds(1))

            // A Search button (enabled once a page is loaded): same glass, same confinement.
            notch.select(.search)
            notch.search.session.load("dexma notch")
            for _ in 0..<100 where !(notch.search.hasPage && !notch.search.isLoading) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(800))
            panel.makeFirstResponder(nil)
            try? await Task.sleep(for: .milliseconds(300))
            let actions = geometry.actionBandFrame
            let button = SearchActionsBand.buttonSize
            // Reload: the third of four buttons, right-aligned, 2 pt apart.
            let reload = CGRect(x: actions.maxX - 2 * button.width - 2,
                                y: actions.midY - button.height / 2, width: button.width, height: button.height)
            let reloadLens = notch.band.lens(for: "search.reload")
            if let plain = DebugImages.window(panel) {
                reloadLens.hover(at: CGPoint(x: button.width / 2, y: button.height / 2))
                try? await Task.sleep(for: .milliseconds(170))
                if let image = DebugImages.window(panel) {
                    DebugImages.write(image, dir, "hover-reload")
                    let allowed = reload.insetBy(dx: -ControlLensEffect.margin, dy: -ControlLensEffect.margin)
                    // The live page keeps changing under it: compare the band strip only.
                    let strip = CGRect(x: 0, y: 0, width: CGFloat(image.width),
                                       height: geometry.contentFrame.minY * panel.backingScaleFactor)
                    if let a = image.cropping(to: strip), let b = plain.cropping(to: strip) {
                        print("[hover] reload button breath vs plain (band strip): \(confinement(a, b, allowed: allowed, panel: panel, geometry: geometry))")
                    }
                }
                reloadLens.hover(at: nil)
                try? await Task.sleep(for: .milliseconds(600))
                report("reload button: lens gone after exit", ok: !reloadLens.isActive, reloadLens)
            }
            notch.select(.terminal)
            try? await Task.sleep(for: .milliseconds(800))
            notch.close()
            _ = await notch.waitForRest()
            report("closed: nothing left running", ok: !notch.debugDriver.isAnimating && !lens.isActive, lens)
            NSApp.terminate(nil)
        }
    }

    /// `-bandshot <dir>`: the open panel at rest, for comparing the plain band across builds.
    static func shot(panel: NotchPanel, notch: NotchViewModel, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false
            notch.open()
            _ = await notch.waitForRest()
            panel.makeFirstResponder(nil)
            try? await Task.sleep(for: .milliseconds(500))
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "band") }
            NSApp.terminate(nil)
        }
    }

    // MARK: Checks

    /// 120 Hz pointer moves across `rect` for 1.5 s while keys go to the terminal every 25 ms:
    /// display-link pacing, main-thread passes, and how long each key takes to be handled.
    private static func glide(panel: NotchPanel, notch: NotchViewModel, session: ShellSession,
                              over rect: CGRect, lens: ControlLens) async {
        let probe = FramePacingProbe(driver: notch.debugDriver)
        probe.startSeries()
        var keyTimes: [Double] = []
        let start = CACurrentMediaTime()
        var step = 0
        while CACurrentMediaTime() - start < 1.5 {
            let t = CACurrentMediaTime() - start
            let x = 6 + (rect.width - 12) * CGFloat(0.5 + 0.5 * sin(t * 2 * .pi / 0.75))
            lens.hover(at: CGPoint(x: x, y: rect.height / 2 + 3 * CGFloat(sin(t * 9))))
            if step % 3 == 0 {
                let keyStart = CACurrentMediaTime()
                type(panel, step % 2 == 0 ? "a" : "b")
                keyTimes.append((CACurrentMediaTime() - keyStart) * 1000)
            }
            step += 1
            try? await Task.sleep(for: .milliseconds(8))
        }
        let intervals = zip(probe.stamps.dropFirst(), probe.stamps).map { ($0 - $1) * 1000 }
        probe.stop()
        let period = intervals.min() ?? 8.33
        print(String(format: "[hover] glide: %d frames, %d late (>1.5×), worst %.2f ms; main-thread pass p95 %.2f / max %.2f ms; %d keys handled in p95 %.2f / max %.2f ms; lens centre followed to x=%.1f",
                     intervals.count, intervals.filter { $0 > period * 1.5 }.count, intervals.max() ?? 0,
                     FramePacingProbe.percentile(probe.passes, 0.95), probe.passes.max() ?? 0,
                     keyTimes.count, FramePacingProbe.percentile(keyTimes, 0.95), keyTimes.max() ?? 0,
                     lens.frame.center.x))
        // Clean up the typed letters.
        session.terminalView.process.send(data: ArraySlice(Array("\u{15}".utf8)))
    }

    /// Where `image` differs from `base`: must be inside `allowed` (control + margin), never in
    /// the notch gap or the content card.
    private static func confinement(_ image: CGImage, _ base: CGImage, allowed: CGRect, panel: NSPanel,
                                    geometry: NotchGeometry) -> String {
        guard let diff = DebugImages.differenceBox(image, base) else { return "no difference (or size mismatch)" }
        let scale = panel.backingScaleFactor
        let box = CGRect(x: diff.minX / scale, y: diff.minY / scale,
                         width: (diff.width + 1) / scale, height: (diff.height + 1) / scale)
        let notchGap = CGRect(x: geometry.tabBandFrame.maxX, y: 0,
                              width: geometry.actionBandFrame.minX - geometry.tabBandFrame.maxX,
                              height: geometry.bandHeight)
        let inside = allowed.insetBy(dx: -0.5, dy: -0.5).contains(box)
        let clear = !box.intersects(notchGap) && !box.intersects(geometry.contentFrame)
        return String(format: "%@ differing box (pt) x %.1f…%.1f y %.1f…%.1f; allowed x %.1f…%.1f y %.1f…%.1f; clear of notch gap and card: %@",
                      inside ? "OK  " : "FAIL", box.minX, box.maxX, box.minY, box.maxY,
                      allowed.minX, allowed.maxX, allowed.minY, allowed.maxY, clear ? "yes" : "NO")
    }

    private static func report(_ label: String, ok: Bool, _ lens: ControlLens) {
        let f = lens.frame
        print(String(format: "[hover] %@ %@: active=%@ presence=%.3f strength=%.3f press=%.3f centre=(%.1f, %.1f)",
                     ok ? "OK  " : "FAIL", label, lens.isActive ? "yes" : "no", f.presence, f.strength, f.press,
                     f.center.x, f.center.y))
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        guard let r = DebugImages.difference(a, b, channels: 4) else { return "size mismatch" }
        return "\(r.differing) px differ by >2/255 \(r.box), max channel diff \(r.maxDiff)"
    }

    // MARK: Synthetic events (sent to the panel only)

    /// `point` in panel coordinates (top-left origin) → the window's (bottom-left).
    private static func windowPoint(_ panel: NSPanel, _ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: panel.frame.height - point.y)
    }

    /// Keeps SwiftUI's own hover state out of the way (the pointer far from every control).
    private static func moveOut(_ panel: NSPanel) {
        send(panel, .mouseMoved, at: CGPoint(x: 30, y: panel.frame.height - 30))
    }

    private static func click(_ panel: NSPanel, at point: CGPoint, down: Bool) {
        send(panel, down ? .leftMouseDown : .leftMouseUp, at: point)
    }

    private static func send(_ panel: NSPanel, _ type: NSEvent.EventType, at point: CGPoint) {
        guard let event = NSEvent.mouseEvent(with: type, location: windowPoint(panel, point), modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                             clickCount: type == .mouseMoved ? 0 : 1,
                                             pressure: type == .leftMouseDown ? 1 : 0) else { return }
        panel.sendEvent(event)
    }

    private static func type(_ panel: NSPanel, _ key: String) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: panel.windowNumber, context: nil, characters: key,
                                               charactersIgnoringModifiers: key, isARepeat: false,
                                               keyCode: key == "a" ? 0 : 11) else { continue }
            panel.sendEvent(event)
        }
    }
}
#endif
