#if DEBUG
import AppKit
import SwiftTerm
import WebKit

/// Debug-only: `DEXMA -swipetest <dir>` swipes between tabs with synthetic trackpad scroll
/// events (phased, precise deltas) posted to DEXMA's own event queue, so they go through the
/// real local monitor (the cursor isn't moved). Checks commits by distance and by flick, the
/// return from a half swipe, rubber-banding, vertical scrolling passing through, web pages that
/// scroll sideways keeping the swipe, interruption, momentum, and frame pacing. Prints
/// `[swipe] …` lines and PNGs, then quits.
enum SwipeTest {
    static func run(panel: NotchPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false
            session.terminalView.process.send(data: ArraySlice(Array("clear; seq 1 200\r".utf8)))
            try? await Task.sleep(for: .seconds(1))
            notch.open()
            _ = await notch.waitForRest()
            let card = notch.geometry.contentFrame
            let overTerminal = CGPoint(x: card.midX, y: card.midY)
            let overBand = CGPoint(x: card.minX + 40, y: notch.geometry.bandHeight / 2)
            report("open on the terminal", ok: notch.tab == .terminal && notch.tabProgress == 0, notch)

            // Slow drag past the commit fraction (45 % of a page) over the terminal.
            let probe = FramePacingProbe(driver: notch.debugTabDriver)
            probe.startSeries()
            await swipe(panel, at: overTerminal, dx: -card.width * 0.45, steps: 40, dt: 0.012, halfway: {
                if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "swipe-halfway") }
                print(String(format: "[swipe]   halfway: tabProgress %.3f, indicator stretch %.3f",
                             notch.tabProgress, notch.band.indicator.stretch))
            })
            _ = await waitForTabs(notch)
            report("slow drag 45 % → Search", ok: notch.tab == .search && notch.tabProgress == 1
                   && session.container.isHidden && !notch.search.session.card.isHidden, notch)
            let intervals = zip(probe.stamps.dropFirst(), probe.stamps).map { ($0 - $1) * 1000 }
            probe.stop()
            let period = intervals.min() ?? 8.33
            print(String(format: "[swipe] pacing (drag + settle): %d frames, %d late (>1.5×), worst %.2f ms; main-thread pass p95 %.2f / max %.2f ms",
                         intervals.count, intervals.filter { $0 > period * 1.5 }.count, intervals.max() ?? 0,
                         FramePacingProbe.percentile(probe.passes, 0.95), probe.passes.max() ?? 0))

            // A half swipe back that stops before the commit fraction: stays on Search.
            await swipe(panel, at: overBand, dx: card.width * 0.25, steps: 25, dt: 0.012, pauseBeforeLift: 0.15)
            _ = await waitForTabs(notch)
            report("drag back 25 % and stop → stays on Search", ok: notch.tab == .search && notch.tabProgress == 1, notch)

            // A short quick flick back (15 % in ~60 ms): commits by speed.
            await swipe(panel, at: overBand, dx: card.width * 0.15, steps: 7, dt: 0.008)
            _ = await waitForTabs(notch)
            report("quick flick 15 % → Terminal", ok: notch.tab == .terminal && notch.tabProgress == 0, notch)

            // Past the first tab: rubber band, then back.
            var lowest: CGFloat = 0
            await swipe(panel, at: overTerminal, dx: card.width * 0.6, steps: 30, dt: 0.01, each: {
                lowest = min(lowest, notch.tabProgress)
            })
            _ = await waitForTabs(notch)
            report(String(format: "past the first tab: lowest %.3f (limit −%.2f), back to 0", lowest,
                          notch.gestureTuning.rubberBandLimit),
                   ok: lowest < 0 && lowest >= -notch.gestureTuning.rubberBandLimit - 0.001
                   && notch.tab == .terminal && notch.tabProgress == 0, notch)

            // Vertical scrolling over the terminal passes through: no tab change, it scrolls.
            let before = session.terminalView.scrollPosition
            await swipe(panel, at: overTerminal, dx: 0.5, dy: 6, steps: 30, dt: 0.01)
            try? await Task.sleep(for: .milliseconds(300))
            report(String(format: "vertical scroll passes through (terminal scroll %.2f → %.2f)", before,
                          session.terminalView.scrollPosition),
                   ok: notch.tab == .terminal && notch.tabProgress == 0, notch)

            // A web page that scrolls sideways keeps the swipe until its edge.
            notch.select(.search)
            _ = await waitForTabs(notch)
            let web = notch.search.session
            web.card.showsPage = true
            web.webView.loadHTMLString("""
                <html><body style="margin:0;width:3000px;height:200px;background:linear-gradient(90deg,#123,#456)">
                wide</body></html>
                """, baseURL: nil)
            try? await Task.sleep(for: .seconds(1.5))
            let overPage = CGPoint(x: card.midX, y: card.maxY - 60)
            await swipe(panel, at: overPage, dx: -card.width * 0.5, steps: 30, dt: 0.01)
            try? await Task.sleep(for: .milliseconds(500))
            let scrolled = try? await web.webView.evaluateJavaScript("window.scrollX") as? Double
            report(String(format: "sideways-scrolling page: page scrolled to x=%.0f, tabs stay", scrolled ?? -1),
                   ok: notch.tab == .search && notch.tabProgress == 1 && (scrolled ?? 0) > 0, notch)
            _ = try? await web.webView.evaluateJavaScript("window.scrollTo(3000, 0)")
            try? await Task.sleep(for: .milliseconds(500))
            await swipe(panel, at: overPage, dx: -card.width * 0.5, steps: 30, dt: 0.01)
            _ = await waitForTabs(notch)
            report("…at its right edge the swipe moves the tabs (rubber band past the last, back)",
                   ok: notch.tab == .search && notch.tabProgress == 1, notch)
            _ = try? await web.webView.evaluateJavaScript("window.scrollTo(0, 0)")
            try? await Task.sleep(for: .milliseconds(500))
            await swipe(panel, at: overPage, dx: card.width * 0.5, steps: 30, dt: 0.01)
            _ = await waitForTabs(notch)
            report("…and at its left edge a swipe right goes to the Terminal", ok: notch.tab == .terminal, notch)

            // Interrupt a click-started switch with a swipe the other way.
            notch.select(.search)
            try? await Task.sleep(for: .milliseconds(90))
            let grabbedAt = notch.tabProgress
            await swipe(panel, at: overBand, dx: card.width * 0.5, steps: 25, dt: 0.01)
            _ = await waitForTabs(notch)
            report(String(format: "grabbed mid-switch at %.2f and swiped back → Terminal", grabbedAt),
                   ok: grabbedAt > 0.05 && grabbedAt < 0.95 && notch.tab == .terminal && notch.tabProgress == 0, notch)

            // Momentum after the fingers lift never moves the tabs.
            await swipe(panel, at: overBand, dx: -card.width * 0.5, steps: 25, dt: 0.01)
            for _ in 0..<20 { post(phase: 0, momentum: 2, dx: -30, dy: 0, at: overBand, panel: panel) }
            _ = await waitForTabs(notch)
            report("momentum after a swipe doesn't move the tabs", ok: notch.tab == .search && notch.tabProgress == 1, notch)

            notch.select(.terminal)
            _ = await waitForTabs(notch)
            notch.close()
            _ = await notch.waitForRest()
            report("closed", ok: session.container.isHidden && notch.search.session.card.isHidden, notch)
            NSApp.terminate(nil)
        }
    }

    // MARK: Events

    /// One gesture: began, `steps` changes of (dx, dy)/steps each `dt` apart, ended.
    private static func swipe(_ panel: NSPanel, at point: CGPoint, dx: CGFloat, dy: CGFloat = 0, steps: Int,
                              dt: Double, pauseBeforeLift: Double = 0, halfway: (() -> Void)? = nil,
                              each: (() -> Void)? = nil) async {
        let sx = dx / CGFloat(steps), sy = dy / CGFloat(steps)
        post(phase: 128, dx: 0, dy: 0, at: point, panel: panel)  // mayBegin
        post(phase: 1, dx: sx, dy: sy, at: point, panel: panel)
        for i in 1..<steps {
            try? await Task.sleep(for: .seconds(dt))
            post(phase: 2, dx: sx, dy: sy, at: point, panel: panel)
            each?()
            if i == steps / 2 {
                try? await Task.sleep(for: .milliseconds(30))
                halfway?()
            }
        }
        try? await Task.sleep(for: .seconds(max(dt, pauseBeforeLift)))
        post(phase: 4, dx: 0, dy: 0, at: point, panel: panel)
        try? await Task.sleep(for: .milliseconds(20))
    }

    /// A continuous (trackpad) scroll event at `point` (panel coordinates). Phases: 1 began,
    /// 2 changed, 4 ended, 128 may begin; momentum 2 = continuing.
    private static func post(phase: Int64, momentum: Int64 = 0, dx: CGFloat, dy: CGFloat, at point: CGPoint,
                             panel: NSPanel) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = panel.frame
        event.location = CGPoint(x: frame.minX + point.x, y: primaryHeight - (frame.maxY - point.y))
        if let ns = NSEvent(cgEvent: event) { NSApp.postEvent(ns, atStart: false) }
    }

    // MARK: Helpers

    private static func waitForTabs(_ notch: NotchViewModel) async -> Bool {
        for _ in 0..<300 {
            try? await Task.sleep(for: .milliseconds(10))
            if !notch.debugTabDriver.isAnimating { return true }
        }
        return false
    }

    private static func report(_ label: String, ok: Bool, _ notch: NotchViewModel) {
        print(String(format: "[swipe] %@ %@: tab=%@ tabProgress=%.3f stretch=%.4f", ok ? "OK  " : "FAIL", label,
                     "\(notch.tab)", notch.tabProgress, notch.band.indicator.stretch))
    }
}
#endif
