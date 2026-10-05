#if DEBUG
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import WebKit

/// Debug-only: `DEXMA -glasstest <dir>` checks Claude in floating glass in the running app: the
/// look on a light and a dark wallpaper (a stand-in backdrop window, pictures of the real screen:
/// launch with `open` for Screen Recording), measured against Spotlight; presenting, focus, the
/// keys, the card morph, typing (⇧Return), the text going into claude.ai (cleared, not sent), the
/// fallback when sending fails, the capture hand-off into the chip, the notch handing the Claude
/// tab over, click-outside, Reduce Motion, and frame pacing. `-glasssend` also sends one real
/// message ("Reply with just: OK") and checks it went. Writes `<dir>/report.txt` and PNGs, quits.
enum GlassTest {
    @MainActor private static var lines: [String] = []

    /// Everything a step needs.
    @MainActor private struct Context {
        let glass: ClaudeGlassViewModel
        let notch: NotchViewModel
        let capture: CaptureViewModel
        let dir: URL
        let screen: NSScreen
        let backdrop: Backdrop
        let field: CGRect
        let card: CGRect
        var panel: FloatingGlassPanel { glass.glass.panel }
        var web: WKWebView { glass.claude.session.webView }
    }

    static func run(glass: ClaudeGlassViewModel, notch: NotchViewModel, capture: CaptureViewModel,
                    settings: AppSettings, dir: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            notch.closesOnFocusLoss = false
            await waitForLoad(glass.claude.session.webView)
            log("claude.ai: \(glass.claude.session.webView.url?.absoluteString ?? "-")")
            let screen = FloatingGlassController.screenWithPointer()
            let layout = glass.glass.layout
            let context = Context(glass: glass, notch: notch, capture: capture, dir: dir, screen: screen,
                                  backdrop: Backdrop(screen: screen), field: layout.onScreen(layout.field),
                                  card: layout.onScreen(layout.card))
            measurements(context)
            if ProcessInfo.processInfo.arguments.contains("-glassfallback") {
                await fallbackLook(context)
                return
            }
            let pacingOnly = ProcessInfo.processInfo.arguments.contains("-glasspacing")
            if !pacingOnly { await looks(context) }
            if !pacingOnly { await conversationLook(context) }
            await pacing(context)
            if pacingOnly {
                context.backdrop.hide()
                try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            await keys(context)
            await fallback(context)
            await captureHandOff(context)
            await notchHandOff(context)
            await reduceMotion(context)
            await settingOff(context, settings: settings)
            if ProcessInfo.processInfo.arguments.contains("-glasssend") { await realSend(context) }
            context.backdrop.hide()
            log("done")
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    /// Layout vs Spotlight (measured: 640 × 56 at (436, 203) on the 1512 × 982 screen).
    @MainActor private static func measurements(_ c: Context) {
        let top = c.screen.frame.maxY - c.field.maxY
        log(String(format: "field on screen: x %.1f, top %.1f, %.0f × %.0f (Spotlight: x 436, top 203, 640 × 56)",
                   c.field.minX - c.screen.frame.minX, top, c.field.width, c.field.height))
        log(String(format: "card: top %.1f, %.0f × %.0f, radius %.0f; buttons %.0f pt, %.0f apart",
                   c.screen.frame.maxY - c.card.maxY, c.card.width, c.card.height, GlassMetrics.cardRadius,
                   GlassMetrics.buttonSize, GlassMetrics.buttonGap))
    }

    /// Compact and expanded over a light and a dark wallpaper, then the light appearance.
    @MainActor private static func looks(_ c: Context) async {
        let glass = c.glass
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        if c.web.url?.path != "/new" {
            glass.claude.newChat()
            await waitForLoad(c.web)
        }
        let layout = glass.glass.layout
        let withButtons = layout.onScreen(CGRect(x: 0, y: 0, width: layout.windowFrame.width, height: layout.field.maxY + 40))
        for (name, image) in [("light", Backdrop.light), ("dark", Backdrop.dark)] {
            c.backdrop.show(image)
            try? await Task.sleep(for: .milliseconds(400))
            glass.present(on: c.screen, compact: true)
            try? await Task.sleep(for: .milliseconds(900))
            if name == "light" {
                let stillFront = NSWorkspace.shared.frontmostApplication?.localizedName == frontmost
                check("presented: key, field focused, \(frontmost) still frontmost",
                      c.panel.isKeyWindow && c.panel.firstResponder === glass.textView && stillFront)
            }
            await shoot(c, rect: c.field.insetBy(dx: -24, dy: -24), name: "glass-compact-\(name)")
            await shoot(c, rect: withButtons, name: "glass-compact-buttons-\(name)")
            glass.expand()
            try? await Task.sleep(for: .milliseconds(1100))
            await shoot(c, rect: c.field.union(c.card).insetBy(dx: -24, dy: -24), name: "glass-expanded-\(name)")
            glass.collapse()
            try? await Task.sleep(for: .milliseconds(700))
            glass.dismiss()
            try? await Task.sleep(for: .milliseconds(700))
        }
        check("dismissed: ordered out, not key", !c.panel.isVisible && !c.panel.isKeyWindow)
        c.backdrop.show(Backdrop.light)
        c.panel.appearance = NSAppearance(named: .aqua)
        glass.present(on: c.screen, compact: true)
        try? await Task.sleep(for: .milliseconds(900))
        await shoot(c, rect: c.field.insetBy(dx: -24, dy: -24), name: "glass-compact-light-appearance")
        glass.dismiss()
        try? await Task.sleep(for: .milliseconds(700))
        c.panel.appearance = nil
    }

    /// `-glassconversation <url>`: an existing conversation in the card (it opens by itself), over
    /// both wallpapers, then back to a new chat.
    @MainActor private static func conversationLook(_ c: Context) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-glassconversation"), index + 1 < arguments.count,
              let url = URL(string: arguments[index + 1]) else { return }
        c.glass.claude.session.load(url)
        await waitForLoad(c.web)
        for (name, image) in [("light", Backdrop.light), ("dark", Backdrop.dark)] {
            c.backdrop.show(image)
            try? await Task.sleep(for: .milliseconds(400))
            c.glass.present(on: c.screen)
            try? await Task.sleep(for: .milliseconds(1500))
            if name == "light" { check("a conversation open: presented with the card", c.glass.isExpanded) }
            await shoot(c, rect: c.field.union(c.card).insetBy(dx: -24, dy: -24), name: "glass-conversation-\(name)")
            c.glass.dismiss()
            try? await Task.sleep(for: .milliseconds(700))
        }
        c.glass.claude.newChat()
        await waitForLoad(c.web)
    }

    /// The pre-macOS 26 look (the popover material), forced on 26: compact and expanded, light and dark.
    @MainActor private static func fallbackLook(_ c: Context) async {
        GlassFallback.isForced = true
        if c.web.url?.path != "/new" {
            c.glass.claude.newChat()
            await waitForLoad(c.web)
        }
        for (name, image) in [("light", Backdrop.light), ("dark", Backdrop.dark)] {
            c.backdrop.show(image)
            try? await Task.sleep(for: .milliseconds(400))
            c.glass.present(on: c.screen, compact: true)
            try? await Task.sleep(for: .milliseconds(900))
            c.glass.expand()
            try? await Task.sleep(for: .milliseconds(1100))
            await shoot(c, rect: c.field.union(c.card).insetBy(dx: -24, dy: -24), name: "fallback-expanded-\(name)")
            c.glass.collapse()
            try? await Task.sleep(for: .milliseconds(700))
            await shoot(c, rect: c.field.insetBy(dx: -24, dy: -24), name: "fallback-compact-\(name)")
            c.glass.dismiss()
            try? await Task.sleep(for: .milliseconds(700))
        }
        c.backdrop.hide()
        try? lines.joined(separator: "\n").write(to: c.dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Frame pacing: present, expand, collapse, dismiss, three times (the first time apart: it
    /// includes the web card's first showing).
    @MainActor private static func pacing(_ c: Context) async {
        c.backdrop.show(Backdrop.dark)
        try? await Task.sleep(for: .milliseconds(500))  // Its picture is drawn.
        // The backdrop's display link: it keeps firing while the glass is ordered out.
        let probe = PacingProbe(window: c.backdrop.window)
        probe.watchMainThread()
        for round in 0..<4 {
            probe.mark("present \(round)")
            let begin = CACurrentMediaTime()
            c.glass.present(on: c.screen, compact: true)
            log(String(format: "  present() call: %.1f ms", (CACurrentMediaTime() - begin) * 1000))
            try? await Task.sleep(for: .milliseconds(600))
            probe.mark("expand \(round)")
            c.glass.expand()
            try? await Task.sleep(for: .milliseconds(800))
            probe.mark("collapse \(round)")
            let collapseBegin = CACurrentMediaTime()
            c.glass.collapse()
            log(String(format: "  collapse() call: %.1f ms", (CACurrentMediaTime() - collapseBegin) * 1000))
            if round == 3 {
                // Where its long pass falls: the fade's end is at 120 ms, the card's removal right after.
                let start = CACurrentMediaTime()
                try? await Task.sleep(for: .milliseconds(700))
                for pass in probe.longPasses where pass.0 + pass.1 >= start - 0.05 {
                    log(String(format: "  collapse 3: %.0f ms pass at +%.0f ms", pass.1 * 1000, (pass.0 - start) * 1000))
                }
            } else {
                try? await Task.sleep(for: .milliseconds(700))
            }
            probe.mark("dismiss \(round)")
            let dismissBegin = CACurrentMediaTime()
            c.glass.dismiss()
            log(String(format: "  dismiss() call: %.1f ms", (CACurrentMediaTime() - dismissBegin) * 1000))
            try? await Task.sleep(for: .milliseconds(600))
        }
        probe.mark("end")
        for line in probe.summary() { log(line) }
        probe.stop()
    }

    /// ⇧Return, ⌘↓ / ⌘↑, the text into claude.ai (cleared), the hidden composer, the see-through page, Esc.
    @MainActor private static func keys(_ c: Context) async {
        let glass = c.glass
        glass.present(on: c.screen, compact: true)
        try? await Task.sleep(for: .milliseconds(600))
        let end = NSRange(location: NSNotFound, length: 0)
        glass.textView.string = ""
        glass.textView.insertText("line one", replacementRange: end)
        key(kVK_Return, flags: [.shift], characters: "\r", to: c.panel)
        glass.textView.insertText("line two", replacementRange: end)
        try? await Task.sleep(for: .milliseconds(300))
        check("⇧Return: a new line, the field grows to 2 lines (\(Int(glass.fieldHeight)) pt)",
              glass.textView.string == "line one\nline two" && glass.fieldHeight > GlassMetrics.fieldHeight + 20)
        await shoot(c, rect: c.field.insetBy(dx: -24, dy: -24).offsetBy(dx: 0, dy: -40).insetBy(dx: 0, dy: -20),
                    name: "glass-two-lines")
        key(kVK_DownArrow, flags: [.command], characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), to: c.panel)
        try? await Task.sleep(for: .milliseconds(700))
        check("⌘↓ opens the card", glass.isExpanded)
        key(kVK_UpArrow, flags: [.command], characters: String(UnicodeScalar(NSUpArrowFunctionKey)!), to: c.panel)
        try? await Task.sleep(for: .milliseconds(700))
        check("⌘↑ closes the card", !glass.isExpanded)

        let typed = await glass.debugComposer.insert("Hello from the glass field\nsecond line")
        check("text goes into claude.ai's message box (2 lines)", typed)
        _ = await glass.debugComposer.insert("")
        try? await Task.sleep(for: .seconds(2))  // claude.ai saves the (now empty) draft, debounced.
        let hidden = (try? await c.web.evaluateJavaScript(hiddenScript) as? String) ?? "-"
        check("claude.ai's own composer is out of sight while the native field works (\(hidden))", hidden == "hidden")
        let clear = (try? await c.web.evaluateJavaScript(clearScript) as? String) ?? "-"
        check("see-through page: body \(clear)", clear.hasPrefix("rgba(0, 0, 0, 0)"))
        key(kVK_Escape, flags: [], characters: "\u{1b}", to: c.panel)
        try? await Task.sleep(for: .milliseconds(700))
        check("Esc hides it", !glass.isPresented && !c.panel.isVisible)
    }

    private static let hiddenScript = """
        (function(){var c=document.querySelector('[data-dexma-composer]'); if(!c) return 'untagged';
         var r=c.getBoundingClientRect();
         return document.documentElement.hasAttribute('data-dexma-native') && r.right < 0 ? 'hidden' : 'visible';})()
        """
    private static let clearScript = """
        (function(){return getComputedStyle(document.body).backgroundColor + ' / '
          + document.querySelectorAll('[data-dexma-plain]').length + ' cleared';})()
        """
    private static let breakSendScript = """
        document.querySelectorAll('[data-testid="chat-input-send"], button[aria-label="Send message"]').forEach(function(b){
          b.setAttribute('data-testid','dexma-test-hidden'); b.setAttribute('aria-label','x'); });
        """

    /// The send button gone (the page "changed"): claude.ai's own box comes back with the text.
    @MainActor private static func fallback(_ c: Context) async {
        let glass = c.glass
        glass.present(on: c.screen, compact: true)
        try? await Task.sleep(for: .milliseconds(600))
        _ = try? await c.web.evaluateJavaScript(breakSendScript)
        glass.textView.string = "fallback check"
        glass.textView.didChangeText()
        log("fallback: first responder \(c.panel.firstResponder.map { "\(type(of: $0))" } ?? "nil")")
        key(kVK_Return, flags: [], characters: "\r", to: c.panel)
        try? await Task.sleep(for: .milliseconds(200))
        log("fallback: sending \(glass.isSending), native \(glass.debugIsNativeComposer)")
        for _ in 0..<200 where glass.isSending || glass.debugIsNativeComposer {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(600))
        log("fallback: after: sending \(glass.isSending), native \(glass.debugIsNativeComposer), expanded \(glass.isExpanded)")
        let editor = (try? await c.web.evaluateJavaScript(
            "document.querySelector('[data-testid=\"chat-input\"]').innerText") as? String) ?? "-"
        let shown = (try? await c.web.evaluateJavaScript(
            "!document.documentElement.hasAttribute('data-dexma-native')") as? Bool) ?? false
        let pageHasKeyboard = (c.panel.firstResponder as? NSView)?.isDescendant(of: c.web) == true
        let ok = shown && editor.contains("fallback check") && glass.textView.string == "fallback check"
            && pageHasKeyboard && glass.isExpanded
        check("fallback: claude.ai's box shown (\(shown)), the text in it, the field keeps it, the page has the keyboard (\(pageHasKeyboard)), card open", ok)
        await shoot(c, rect: c.field.union(c.card).insetBy(dx: -24, dy: -24), name: "glass-fallback")
        _ = await glass.debugComposer.insert("")
        try? await Task.sleep(for: .seconds(2))  // claude.ai saves the (now empty) draft, debounced.
        glass.textView.string = ""
        glass.dismiss()
        c.web.reload()
        await waitForLoad(c.web)
    }

    /// Draw to ask: the picture flies onto the chip; the glass comes up compact with it, field focused.
    @MainActor private static func captureHandOff(_ c: Context) async {
        let glass = c.glass
        c.capture.debugBegin(on: c.screen, frozen: CaptureTest.syntheticFrozen(for: c.screen), delay: 0.05)
        try? await Task.sleep(for: .milliseconds(500))
        let overlay = c.capture.debugPanel
        let stroke: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.02).map { (t: Double) -> CGPoint in
            let wave: Double = 120 * sin(t * Double.pi * 2)
            return CGPoint(x: 330 + 460 * t, y: 280 + wave + 140 * t)
        }
        mouse(.leftMouseDown, stroke[0], to: overlay)
        for point in stroke.dropFirst() { mouse(.leftMouseDragged, point, to: overlay) }
        mouse(.leftMouseUp, stroke[stroke.count - 1], to: overlay)
        var shotMidFlight = false
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(50))
            if !shotMidFlight, c.capture.phase == .flying {
                shotMidFlight = true
                try? await Task.sleep(for: .milliseconds(260))
                await shoot(c, rect: c.field.insetBy(dx: -120, dy: -180), name: "glass-capture-landing")
            }
            if c.capture.phase == .idle, glass.isPresented { break }
        }
        try? await Task.sleep(for: .milliseconds(700))
        check("capture: glass up, compact, chip attached, field focused, overlay gone",
              glass.isPresented && !glass.isExpanded && glass.attachment != nil
                && c.panel.firstResponder === glass.textView && !overlay.isVisible)
        c.backdrop.show(Backdrop.dark)
        try? await Task.sleep(for: .milliseconds(400))
        await shoot(c, rect: c.field.insetBy(dx: -24, dy: -24), name: "glass-chip")
        // Click outside (another window takes the keyboard) hides it.
        c.backdrop.window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))
        check("click outside (losing the keyboard) hides it", !glass.isPresented)
        glass.removeAttachment()
    }

    /// The notch hands the Claude tab over; the other tabs stay in the notch.
    @MainActor private static func notchHandOff(_ c: Context) async {
        let notch = c.notch
        notch.open()
        _ = await notch.waitForRest()
        notch.select(.search)
        try? await Task.sleep(for: .milliseconds(600))
        check("notch: Search still a notch tab", notch.tab == .search && notch.isOpen)
        notch.select(.claude)
        try? await Task.sleep(for: .milliseconds(900))
        check("notch: Claude tab → the notch closes, the glass comes up with the keyboard",
              !notch.isOpen && notch.tab == .search && c.glass.isPresented && c.panel.isKeyWindow)
        c.glass.dismiss()
        try? await Task.sleep(for: .milliseconds(600))
        notch.select(.terminal)
    }

    /// The setting off: Claude is a notch tab again (its card back in the pager, dark, opaque, its
    /// own composer shown); on again: back in the glass. The preference is removed afterwards.
    @MainActor private static func settingOff(_ c: Context, settings: AppSettings) async {
        let card = c.glass.claude.session.card
        settings.claudeInGlass = false
        try? await Task.sleep(for: .milliseconds(300))
        c.notch.open()
        _ = await c.notch.waitForRest()
        c.notch.select(.claude)
        try? await Task.sleep(for: .milliseconds(900))
        let native = (try? await c.web.evaluateJavaScript(
            "document.documentElement.hasAttribute('data-dexma-native')") as? Bool) ?? true
        check("setting off: Claude opens in the notch (card in the notch, composer shown), no glass",
              c.notch.tab == .claude && c.notch.isOpen && card.window === c.notch.debugPanel && !card.isHidden
                && card.drawsCardBackground && !native && !c.glass.isPresented)
        c.notch.select(.terminal)
        c.notch.close()
        _ = await c.notch.waitForRest()
        settings.claudeInGlass = true
        UserDefaults.standard.removeObject(forKey: "claudeInGlass")
        try? await Task.sleep(for: .milliseconds(300))
        c.glass.present(on: c.screen)
        try? await Task.sleep(for: .milliseconds(700))
        check("setting on again: the card is in the glass, the glass comes up",
              card.window === c.panel && c.glass.isPresented && !card.drawsCardBackground)
        c.glass.dismiss()
        try? await Task.sleep(for: .milliseconds(600))
    }

    @MainActor private static func reduceMotion(_ c: Context) async {
        c.glass.glass.debugReduceMotion = true
        c.glass.present(on: c.screen, compact: true)
        try? await Task.sleep(for: .milliseconds(600))
        check("Reduce Motion: presents with fades only", c.glass.isPresented && c.glass.glass.reduceMotion)
        c.glass.dismiss()
        try? await Task.sleep(for: .milliseconds(500))
        c.glass.glass.debugReduceMotion = nil
    }

    /// One real message from the field, sent and checked; the card shows the answer.
    @MainActor private static func realSend(_ c: Context) async {
        let glass = c.glass
        let web = c.web
        glass.claude.newChat()
        await waitForLoad(web)
        try? await Task.sleep(for: .seconds(1.5))
        glass.present(on: c.screen, compact: true)
        try? await Task.sleep(for: .milliseconds(600))
        glass.textView.string = "Reply with just: OK"
        let before = web.url?.path ?? "-"
        key(kVK_Return, flags: [], characters: "\r", to: glass.glass.panel)
        for _ in 0..<300 where glass.isSending { try? await Task.sleep(for: .milliseconds(100)) }
        let users = (try? await web.evaluateJavaScript(
            "document.querySelectorAll('[data-testid=\"user-message\"]').length") as? Int) ?? 0
        check("real send: sent (field cleared, \(users) user message, \(before) → \(web.url?.path ?? "-")), card open, still native",
              glass.textView.string.isEmpty && users >= 1 && glass.isExpanded && glass.debugIsNativeComposer)
        try? await Task.sleep(for: .seconds(8))  // The answer.
        let reply = (try? await web.evaluateJavaScript(
            "(document.querySelector('.font-claude-response, .font-claude-message, [data-is-streaming]') || {}).innerText || ''") as? String) ?? ""
        log("reply: \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))")
        await shoot(c, rect: c.field.union(c.card).insetBy(dx: -24, dy: -24), name: "glass-sent")
        glass.dismiss()
        try? await Task.sleep(for: .milliseconds(600))
    }

    // MARK: Helpers

    @MainActor private static func log(_ line: String) {
        print("[glass] \(line)")
        lines.append(line)
    }

    @MainActor private static func check(_ name: String, _ ok: Bool) {
        log("\(ok ? "OK  " : "FAIL") \(name)")
    }

    private static func waitForLoad(_ view: WKWebView) async {
        let end = CACurrentMediaTime() + 30
        try? await Task.sleep(for: .milliseconds(300))
        while CACurrentMediaTime() < end, view.isLoading || view.url == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
        try? await Task.sleep(for: .seconds(1))
    }

    private static func key(_ code: Int, flags: NSEvent.ModifierFlags, characters: String, to window: NSWindow) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: UInt16(code)) else { return }
        if flags.contains(.command), window.performKeyEquivalent(with: event) { return }
        window.sendEvent(event)
    }

    private static func mouse(_ type: NSEvent.EventType, _ point: CGPoint, to window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
            window.sendEvent(event)
        }
    }

    /// The real screen in `rect` (global AppKit coordinates), DEXMA included.
    @MainActor private static func shoot(_ c: Context, rect: CGRect, name: String) async {
        let screen = c.screen, dir = c.dir
        guard let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            log("\(name): no capture (Screen Recording? launch with open)")
            return
        }
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            .intersection(CGRect(origin: .zero, size: screen.frame.size))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = Int(local.width * screen.backingScaleFactor)
        configuration.height = Int(local.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            log("\(name): capture failed")
            return
        }
        DebugImages.write(image, dir, name)
        log(String(format: "%@.png: display points (%.0f, %.0f) %.0f × %.0f", name, local.minX, local.minY, local.width, local.height))
    }

    /// A stand-in wallpaper: a window filling the screen under the glass (above other apps).
    @MainActor private final class Backdrop {
        static let light = "/System/Library/Desktop Pictures/iMac Silver.heic"
        static let dark = "/System/Library/Desktop Pictures/Radial Sky Blue.heic"
        let window: NSWindow
        private let imageView = NSImageView()

        init(screen: NSScreen) {
            window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.frame = CGRect(origin: .zero, size: screen.frame.size)
            window.contentView = imageView
            window.setFrame(screen.frame, display: false)
        }

        func show(_ path: String) {
            if let image = NSImage(contentsOfFile: path) {
                // Fill (crop), like the desktop.
                let size = window.frame.size
                imageView.image = NSImage(size: size, flipped: false) { rect in
                    let scale = max(size.width / image.size.width, size.height / image.size.height)
                    let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                          width: drawn.width, height: drawn.height))
                    _ = rect
                    return true
                }
            }
            window.orderFrontRegardless()
        }

        func hide() {
            window.orderOut(nil)
        }
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    /// Frames of the panel's display link while the glass animates, per action (`mark`): late =
    /// more than 1.5 × the usual interval (the main thread held a frame up).
    @MainActor private final class PacingProbe: NSObject {
        private var link: CADisplayLink?
        private var stamps: [CFTimeInterval] = []
        private var marks: [(String, CFTimeInterval)] = []

        init(window: NSWindow) {
            super.init()
            let link = window.displayLink(target: self, selector: #selector(frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Main run-loop passes longer than 20 ms: (start, length).
        private(set) var longPasses: [(CFTimeInterval, CFTimeInterval)] = []
        private var observer: CFRunLoopObserver?

        func watchMainThread() {
            var passStart: CFTimeInterval = 0
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue
                | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
                let now = CACurrentMediaTime()
                if activity == .afterWaiting { passStart = now } else if passStart > 0, now - passStart > 0.02 {
                    MainActor.assumeIsolated { self?.longPasses.append((passStart, now - passStart)) }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }

        @objc private func frame(_ link: CADisplayLink) {
            stamps.append(link.timestamp)
        }

        func mark(_ label: String) {
            marks.append((label, CACurrentMediaTime()))
        }

        func summary() -> [String] {
            let gaps = zip(stamps, stamps.dropFirst()).map { (time: $1, gap: $1 - $0) }
            guard !gaps.isEmpty else { return ["pacing: no frames"] }
            let usual = gaps.map(\.gap).sorted()[gaps.count / 2]
            var lines = [String(format: "pacing: %d frames, usual %.1f ms", gaps.count, usual * 1000)]
            for (index, (label, start)) in marks.dropLast().enumerated() {
                let end = marks[index + 1].1
                let inside = gaps.filter { $0.time > start && $0.time <= end }
                let late = inside.filter { $0.gap > usual * 1.5 }
                let passes = longPasses.filter { $0.0 >= start && $0.0 < end }.map { String(format: "%.0f", $0.1 * 1000) }
                lines.append(String(format: "  %@: %d frames, %d late, worst %.1f ms; main-thread passes > 20 ms: %@", label,
                                    inside.count, late.count, (inside.map(\.gap).max() ?? 0) * 1000,
                                    passes.isEmpty ? "none" : passes.joined(separator: ", ")))
            }
            return lines
        }

        func stop() {
            link?.invalidate()
            link = nil
        }
    }
}
#endif
