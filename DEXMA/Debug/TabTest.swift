#if DEBUG
import AppKit
import SwiftTerm
import WebKit

/// Debug-only: `DEXMA -tabtest <dir>` checks the tabs and the Search tab in the running app:
/// switching (focus, which view shows), the ⌘-keys, a real Google search, the swipe-to-close
/// rule, and the liquid effect on the Search card (its snapshot vs the window server's own
/// composite, frame pacing, interrupted motions). Prints `[tabs] …` lines and PNGs, then quits.
enum TabTest {
    static func run(panel: NotchPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false  // The Mac may be in use while this runs.
            let search = notch.search.session
            session.terminalView.process.send(data: ArraySlice(Array("clear; echo tab test\r".utf8)))
            try? await Task.sleep(for: .seconds(1))
            notch.open()
            _ = await notch.waitForRest()
            report("terminal tab, open", ok: notch.tab == .terminal && !session.container.isHidden
                   && search.card.isHidden && panel.firstResponder === session.terminalView, panel, notch)
            capture(panel, dir, "terminal-open")

            press("2", panel)
            try? await Task.sleep(for: .seconds(1))  // The indicator has settled.
            report("⌘2 → Search tab, field focused", ok: notch.tab == .search && session.container.isHidden
                   && !search.card.isHidden && fieldFocused(search, panel), panel, notch)
            capture(panel, dir, "search-empty")
            report("swipe up closes with no page", ok: notch.canCloseBySwipe, panel, notch)
            await restSwap("search empty", panel: panel, notch: notch, dir: dir)

            press("1", panel)
            try? await Task.sleep(for: .milliseconds(200))
            report("⌘1 → Terminal tab", ok: notch.tab == .terminal && search.card.isHidden
                   && panel.firstResponder === session.terminalView, panel, notch)
            press("l", panel)
            try? await Task.sleep(for: .milliseconds(200))
            report("⌘L → Search tab, field focused", ok: notch.tab == .search && fieldFocused(search, panel),
                   panel, notch)

            let query = "liquid glass macOS"
            search.card.field.stringValue = query
            let started = CACurrentMediaTime()
            search.load(query)
            var loaded = false
            for _ in 0..<150 {
                try? await Task.sleep(for: .milliseconds(100))
                if search.hasPage, !search.isLoading, search.webView.url?.host == "www.google.com" {
                    loaded = true
                    break
                }
            }
            print(String(format: "[tabs] search loaded: %@ in %.1f s, url %@", loaded ? "yes" : "NO",
                         CACurrentMediaTime() - started, search.webView.url?.absoluteString ?? "-"))
            try? await Task.sleep(for: .seconds(2.5))  // Idle: the page's snapshot is retaken.
            report("field shows the search words", ok: search.card.field.stringValue == query, panel, notch)
            report("back/reload state", ok: notch.search.hasPage && !notch.search.canGoForward, panel, notch)
            capture(panel, dir, "search-results")
            // The real screen too (needs Screen Recording: launch with `open`), since the window
            // server's capture of our own window may draw WebKit's remote layers differently.
            if let screen = await DebugImages.screen(around: panel) {
                DebugImages.write(screen, dir, "screen-search-results")
            } else {
                print("[tabs] no real-screen capture (Screen Recording not granted to this launch)")
            }
            report("page at its top: a swipe up scrolls, doesn't close", ok: !notch.canCloseBySwipe, panel, notch)
            _ = try? await search.webView.evaluateJavaScript("window.scrollTo(0, document.documentElement.scrollHeight)")
            try? await Task.sleep(for: .milliseconds(400))
            report("page at its end: a swipe up closes", ok: notch.canCloseBySwipe, panel, notch)
            _ = try? await search.webView.evaluateJavaScript("window.scrollTo(0, 0)")
            try? await Task.sleep(for: .seconds(1.5))

            await restSwap("search page", panel: panel, notch: notch, dir: dir)
            await pacing(notch)
            await interactions(panel: panel, notch: notch)
            await poses(panel: panel, notch: notch, dir: dir)

            // Switching mid-motion: the Search picture takes over at once and the live
            // terminal comes back at rest.
            notch.close()
            try? await Task.sleep(for: .milliseconds(60))
            notch.open()
            try? await Task.sleep(for: .milliseconds(60))
            notch.select(.terminal)
            _ = await notch.waitForRest()
            report("tab switched mid-open ends on the live terminal", ok: notch.tab == .terminal
                   && !notch.effects.isActive && !session.container.isHidden && search.card.isHidden
                   && panel.firstResponder === session.terminalView, panel, notch)
            notch.close()
            _ = await notch.waitForRest()
            report("closed on terminal", ok: session.container.isHidden && search.card.isHidden, panel, notch)
            NSApp.terminate(nil)
        }
    }

    // MARK: Checks

    /// Live card vs the motion layer with every effect at zero, at rest: must match.
    private static func restSwap(_ label: String, panel: NSPanel, notch: NotchViewModel, dir: URL) async {
        guard let live = DebugImages.window(panel) else { return }
        notch.debugBeginMotion()
        try? await Task.sleep(for: .milliseconds(150))
        guard let motion = DebugImages.window(panel) else { return }
        notch.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(150))
        let name = label.replacingOccurrences(of: " ", with: "-")
        DebugImages.write(live, dir, "rest-\(name)-live")
        DebugImages.write(motion, dir, "rest-\(name)-motion")
        print("[tabs] at rest, \(label), live vs motion layer: \(compare(motion, live))")
    }

    private static func pacing(_ notch: NotchViewModel) async {
        let probe = FramePacingProbe(driver: notch.debugDriver)
        var intervals: [Double] = []
        var notes: [String] = []
        for _ in 0..<3 {
            for open in [false, true] {
                probe.startSeries()
                let start = CACurrentMediaTime()
                if open { notch.open() } else { notch.close() }
                let call = (CACurrentMediaTime() - start) * 1000
                _ = await notch.waitForRest()
                let these = zip(probe.stamps.dropFirst(), probe.stamps).map { ($0 - $1) * 1000 }
                let late = these.enumerated().filter { $0.element > 12.5 }
                    .map { String(format: "frame %d/%d %.1f ms", $0.offset + 1, these.count, $0.element) }
                notes.append(String(format: "%@ call %.1f ms%@", open ? "open" : "close", call,
                                    late.isEmpty ? "" : " late: " + late.joined(separator: ", ")))
                intervals += these
            }
        }
        probe.stop()
        let period = intervals.min() ?? 8.33
        print("[tabs]   \(notes.joined(separator: "; "))")
        print(String(format: "[tabs] pacing on Search: %d frames, %d late (>1.5×), worst %.2f ms; run-loop pass p95 %.2f / max %.2f ms",
                     intervals.count, intervals.filter { $0 > period * 1.5 }.count, intervals.max() ?? 0,
                     FramePacingProbe.percentile(probe.passes, 0.95), probe.passes.max() ?? 0))
    }

    private static func interactions(panel: NotchPanel, notch: NotchViewModel) async {
        let card = notch.search.session.card
        func check(_ label: String, open: Bool) {
            report(label, ok: notch.state == (open ? .open : .closed) && notch.progress == (open ? 1 : 0)
                   && !notch.effects.isActive && card.isHidden == !open
                   && (!open || pageFocused(notch.search.session, panel)), panel, notch)
        }
        notch.close()
        try? await Task.sleep(for: .milliseconds(80))
        notch.open()
        _ = await notch.waitForRest()
        check("Search: close → open mid-flight, page keeps the keyboard", open: true)
        notch.beginInteraction()
        for i in 1...10 {
            try? await Task.sleep(for: .milliseconds(8))
            notch.updateInteraction(delta: -0.3 * CGFloat(i) / 10)
        }
        notch.endInteraction(velocity: -4)
        _ = await notch.waitForRest()
        check("Search: flick up closes", open: false)
        notch.open()
        _ = await notch.waitForRest()
        check("Search: open again", open: true)
    }

    private static func poses(panel: NSPanel, notch: NotchViewModel, dir: URL) async {
        notch.debugBeginMotion()
        for (name, progress, effect) in [("opening-60", 0.6, MotionEffects.Frame(stretch: 0.05, bulge: 0, energy: 1)),
                                         ("closing-96", 0.96, MotionEffects.Frame(stretch: 0.03, bulge: 0, energy: 1))] {
            notch.debugPose(progress: progress, effect: effect)
            try? await Task.sleep(for: .milliseconds(120))
            capture(panel, dir, "pose-search-\(name)")
        }
        notch.debugPose(progress: 1, effect: .init())
        notch.debugEndMotion()
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Helpers

    private static func press(_ key: String, _ panel: NotchPanel) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: key, charactersIgnoringModifiers: key,
                                           isARepeat: false, keyCode: 0) else { return }
        _ = panel.performKeyEquivalent(with: event)
    }

    private static func pageFocused(_ search: SearchSession, _ panel: NSPanel) -> Bool {
        (panel.firstResponder as? NSView)?.isDescendant(of: search.webView) ?? false
    }

    private static func fieldFocused(_ search: SearchSession, _ panel: NSPanel) -> Bool {
        (panel.firstResponder as? NSTextView)?.delegate === search.card.field
    }

    private static func report(_ label: String, ok: Bool, _ panel: NSPanel, _ notch: NotchViewModel) {
        let responder = panel.firstResponder.map { "\(type(of: $0))" } ?? "nil"
        print("[tabs] \(ok ? "OK  " : "FAIL") \(label): tab=\(notch.tab) state=\(notch.state) progress=\(notch.progress) motion=\(notch.effects.isActive) key=\(panel.isKeyWindow) firstResponder=\(responder)")
    }

    private static func capture(_ panel: NSPanel, _ dir: URL, _ name: String) {
        if let image = DebugImages.window(panel) { DebugImages.write(image, dir, name) }
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        guard let r = DebugImages.difference(a, b, channels: 4) else { return "size mismatch" }
        return "\(r.differing) px differ by >2/255 \(r.box), max channel diff \(r.maxDiff)"
    }
}
#endif
