#if DEBUG
import AppKit
import WebKit

/// Debug-only: `DEXMA -capturetest <dir>` checks Draw to ask end to end with a synthetic frozen
/// screen (no Screen Recording needed): the overlay's picture (orientation, dim, glow), a long
/// scribble driven at the display's rate (main-thread time per pointer event, late frames), the
/// selection morph and lift, the crop's pixel size, the flight and the hand-off (overlay gone,
/// notch opening on Claude), inserting into a stand-in of claude.ai's composer loaded in the
/// Claude tab (real paste, clipboard restored, focus, the file-input fallback), the pending chip
/// (signed out, timeout, retry), click-to-capture-window, Esc at every stage and Reduce Motion.
/// With DEXMA's Screen Recording grant (launch with `open`), it also times real freezes and checks
/// the notch panel is left out of them. Prints `[capture] …` (and writes `report.txt`), PNGs to
/// `<dir>`, then quits. The user's clipboard is put back at the end.
enum CaptureTest {
    private static var report: [String] = []
    private static var dir = URL(fileURLWithPath: "/tmp")

    static func run(panel: NotchPanel, notch: NotchViewModel, dir: URL) {
        self.dir = dir
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let clipboard = PasteboardSnapshot()
            notch.closesOnFocusLoss = false  // The Mac is often in use while this runs.
            guard let capture = notch.capture, let screen = panel.screen else {
                log("FAIL no capture view model / screen")
                return finish(clipboard)
            }
            let frozen = syntheticFrozen(for: screen)
            let web = notch.claude.session.webView
            web.stopLoading()
            await bandShots(notch: notch, panel: panel, capture: capture)

            // 1. Overlay up, frozen picture in, the right way up.
            await loadStandIn(web, mode: "normal")
            var serverMark = windowServerSeconds()
            try? await Task.sleep(for: .seconds(2))
            log("WindowServer CPU, DEXMA idle (baseline): \(String(format: "%.0f", (windowServerSeconds() - serverMark) / 2 * 100)) %")
            for (name, intensity, still) in [("effects off", 0.0, false), ("effects still (Reduce Motion)", 1.0, true),
                                             ("effects moving", 1.0, false)] {
                capture.effectIntensity = intensity
                capture.debugReduceMotion = still
                capture.debugBegin(on: screen, frozen: frozen, delay: 0.05)
                try? await Task.sleep(for: .seconds(0.8))
                serverMark = windowServerSeconds()
                try? await Task.sleep(for: .seconds(2))
                log("WindowServer CPU, overlay up, \(name): \(String(format: "%.0f", (windowServerSeconds() - serverMark) / 2 * 100)) %")
                capture.cancel()
                try? await Task.sleep(for: .seconds(0.8))
            }
            capture.effectIntensity = 1
            capture.debugReduceMotion = nil
            do {
                // For comparison: any 120 Hz animation costs the window server about this much.
                serverMark = windowServerSeconds()
                let begin = CACurrentMediaTime()
                while CACurrentMediaTime() - begin < 3 {
                    notch.toggle()
                    try? await Task.sleep(for: .seconds(0.3))
                }
                log("WindowServer CPU, notch opening/closing nonstop: \(String(format: "%.0f", (windowServerSeconds() - serverMark) / (CACurrentMediaTime() - begin) * 100)) %")
                notch.close()
                _ = await notch.waitForRest()
            }
            var t0 = CACurrentMediaTime()
            capture.debugBegin(on: screen, frozen: frozen, delay: 0.1)
            log("begin (overlay up) on the main thread: \(ms(CACurrentMediaTime() - t0)) ms")
            try? await Task.sleep(for: .milliseconds(500))
            let overlay = capture.debugPanel
            if let image = DebugImages.window(overlay) {
                DebugImages.write(image, dir, "1-frozen")
                let scale = CGFloat(image.width) / screen.frame.width
                let marker = pixel(image, at: CGPoint(x: 60 * scale, y: 60 * scale))
                let below = pixel(image, at: CGPoint(x: 60 * scale, y: (screen.frame.height - 60) * scale))
                log("orientation: top-left marker \(marker) (red, dimmed, expected), bottom-left \(below) \(marker.r > 150 && marker.g < 60 ? "OK" : "FAIL")")
                log("overlay key \(overlay.isKeyWindow), level \(overlay.level.rawValue), phase \(capture.phase)")
            } else {
                log("FAIL no overlay picture")
            }

            serverMark = windowServerSeconds()
            try? await Task.sleep(for: .seconds(2))
            log("WindowServer CPU, overlay up, not drawing (glow turning, shimmer running): \(String(format: "%.0f", (windowServerSeconds() - serverMark) / 2 * 100)) %")
            // 2. A long scribble at the display's rate.
            let center = CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)
            let scribble = (0..<1200).map { k -> CGPoint in
                let t = CGFloat(k) / 1200 * 2 * .pi * 6
                return CGPoint(x: center.x + 300 * sin(t * 1.03) + 6 * sin(t * 13), y: center.y + 180 * sin(t * 0.71 + 1))
            }
            let serverBefore = windowServerSeconds()
            let drawing = await drive(scribble, on: overlay)
            let serverDrawing = windowServerSeconds() - serverBefore
            log("scribble: \(scribble.count) moves over \(String(format: "%.1f", drawing.seconds)) s, per move p50 \(String(format: "%.2f", drawing.p50)) / p95 \(String(format: "%.2f", drawing.p95)) / max \(String(format: "%.2f", drawing.max)) ms, late frames \(drawing.late) of \(drawing.frames); WindowServer CPU \(String(format: "%.0f", serverDrawing / drawing.seconds * 100)) %")
            if let image = DebugImages.window(overlay) { DebugImages.write(image, dir, "2-drawing") }

            // 3. Release: morph, lift, crop, flight, hand-off, insert.
            let expected = CaptureSelection.rect(around: scribble, in: CGRect(origin: .zero, size: frozen.size))!
            // (The user's clipboard was saved at the start; this marker checks the paste puts it back.)
            let marker = "DEXMA clipboard check \(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(marker, forType: .string)
            capture.debugForgetLastMethod()
            let released = CACurrentMediaTime()
            let serverRelease = windowServerSeconds()
            send(.leftMouseUp, scribble.last!, to: overlay)
            let look = CaptureLook.full
            try? await Task.sleep(for: .seconds(look.morph * 0.5))
            if let image = DebugImages.window(overlay) { DebugImages.write(image, dir, "3-morph") }
            try? await Task.sleep(for: .seconds(look.morph * 0.5 + 0.06))
            log("WindowServer CPU during the morph: \(String(format: "%.0f", (windowServerSeconds() - serverRelease) / (CACurrentMediaTime() - released) * 100)) %")
            if let image = DebugImages.window(overlay) {
                DebugImages.write(image, dir, "4-lifted")
                // Right after the morph the outline is the rectangle: white on each edge's middle.
                let scale = CGFloat(image.width) / screen.frame.width
                let edges = [CGPoint(x: expected.minX, y: expected.midY), CGPoint(x: expected.maxX, y: expected.midY),
                             CGPoint(x: expected.midX, y: expected.minY), CGPoint(x: expected.midX, y: expected.maxY)]
                let found = edges.map { point -> Int in
                    (-10...10).map { d -> Int in
                        let probe = point.x == expected.midX ? CGPoint(x: point.x, y: point.y + CGFloat(d))
                                                              : CGPoint(x: point.x + CGFloat(d), y: point.y)
                        let p = pixel(image, at: CGPoint(x: probe.x * scale, y: probe.y * scale))
                        return min(p.r, p.g, p.b)
                    }.max() ?? 0
                }
                log("outline on the rectangle after the morph (brightest per edge): \(found) \(found.allSatisfy { $0 > 170 } ? "OK" : "FAIL")")
            }
            var overlayGone: CFTimeInterval?, opening: CFTimeInterval?, rest: CFTimeInterval?, flightShot = false
            while CACurrentMediaTime() - released < 4 {
                let now = CACurrentMediaTime() - released
                if !flightShot, capture.phase == .flying {
                    try? await Task.sleep(for: .seconds(look.flight * 0.45))
                    if let image = DebugImages.window(overlay) { DebugImages.write(image, dir, "5-flight") }
                    flightShot = true
                }
                if opening == nil, notch.state == .open { opening = now }
                if overlayGone == nil, opening != nil, !overlay.isVisible { overlayGone = now }
                if opening != nil, rest == nil, notch.progress >= 0.999, !notch.debugDriver.isAnimating { rest = now }
                if rest != nil, overlayGone != nil { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            log("release → notch opening \(ms(opening)) ms, overlay gone \(ms(overlayGone)) ms, panel at rest \(ms(rest)) ms: \((overlayGone ?? 9) < (rest ?? 0) ? "OK (gone first)" : "FAIL")")
            log("tab after landing: \(notch.tab) \(notch.tab == .claude ? "OK" : "FAIL")")
            t0 = CACurrentMediaTime()
            let method = await waitForInsert(capture, web: web, count: 1)
            let received = await receivedImages(web)
            let pixels = CaptureCrop.pixelRect(for: expected, displaySize: frozen.size,
                                               imageSize: CGSize(width: frozen.image.width, height: frozen.image.height))
            log("inserted by \(method.map(\.rawValue) ?? "nothing") in \(ms(CACurrentMediaTime() - t0)) ms after rest; page got \(received.last ?? "nothing"); expected \(Int(pixels.width))×\(Int(pixels.height)) px \(received.last?.contains("\(Int(pixels.width))×\(Int(pixels.height))") == true ? "OK" : "FAIL")")
            log("clipboard restored: \(NSPasteboard.general.string(forType: .string) == marker ? "OK" : "FAIL (\(NSPasteboard.general.string(forType: .string) ?? "nil"))")")
            let focused = try? await web.evaluateJavaScript("document.activeElement && document.activeElement.getAttribute('data-testid')") as? String
            log("caret in the message box: \(focused ?? "nil") \(focused == "chat-input" && panel.firstResponder is WKWebView ? "OK" : "FAIL")")
            log("chip after insert: \(capture.pending == nil ? "none OK" : "FAIL still pending")")
            notch.close()
            _ = await notch.waitForRest()

            // 4. A click picks the window under it.
            await captureOnce(capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch,
                              points: [CGPoint(x: 350, y: 300), CGPoint(x: 351, y: 300)])
            await waitForInsert(capture, web: web, count: 2)
            log("click on a window → page got \((await receivedImages(web)).last ?? "nothing") (expected 1000×640 at 2x) \((await receivedImages(web)).last?.contains("\(Int(500 * screen.backingScaleFactor))×\(Int(320 * screen.backingScaleFactor))") == true ? "OK" : "FAIL")")
            notch.close()
            _ = await notch.waitForRest()

            // 5. Esc at every stage.
            await escapes(capture: capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch, web: web)

            // 6. The file-input fallback (the page ignores a pasted file).
            await loadStandIn(web, mode: "noPaste")
            await captureOnce(capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch, points: scribble.prefix(200).map { $0 })
            let fallback = await waitForInsert(capture, web: web, count: 1)
            log("page ignoring pastes → \(fallback.map(\.rawValue) ?? "nothing"), page got \((await receivedImages(web)).last ?? "nothing") \(fallback == .fileInput ? "OK" : "FAIL")")
            notch.close()
            _ = await notch.waitForRest()

            // 7. Signed out: the chip waits, then attaches once the message box appears.
            await loadStandIn(web, mode: "login")
            await captureOnce(capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch, points: scribble.prefix(300).map { $0 })
            try? await Task.sleep(for: .seconds(2.5))
            log("signed out: chip \(capture.pending.map { "\($0.state)" } ?? "none") \(capture.pending?.state == .waiting ? "OK" : "FAIL")")
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "7-chip") }
            await loadStandIn(web, mode: "normal")
            let late = await waitForInsert(capture, web: web, count: 1)
            log("message box appeared → attached by itself: \(capture.pending == nil && late != nil ? "OK" : "FAIL") (\((await receivedImages(web)).last ?? "nothing"))")
            notch.close()
            _ = await notch.waitForRest()

            // 8. Timeout keeps the chip; a click on it retries.
            capture.debugInsertTimeout = 2
            await loadStandIn(web, mode: "login")
            await captureOnce(capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch, points: scribble.prefix(300).map { $0 })
            try? await Task.sleep(for: .seconds(3.5))
            log("after the timeout: chip \(capture.pending.map { "\($0.state)" } ?? "none") \(capture.pending?.state == .needsRetry ? "OK" : "FAIL")")
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "8-chip-retry") }
            capture.debugInsertTimeout = nil
            await loadStandIn(web, mode: "normal")
            capture.retryPending()
            await waitForInsert(capture, web: web, count: 1)
            log("retry from the chip: \(capture.pending == nil ? "attached OK" : "FAIL") (\((await receivedImages(web)).last ?? "nothing"))")
            notch.close()
            _ = await notch.waitForRest()

            // 9. Reduce Motion: no flight, a quick fade, then the panel opens.
            capture.debugReduceMotion = true
            await loadStandIn(web, mode: "normal")
            let start = CACurrentMediaTime()
            await captureOnce(capture, screen: screen, frozen: frozen, overlay: overlay, notch: notch, points: scribble.prefix(300).map { $0 })
            var opened: CFTimeInterval?
            while CACurrentMediaTime() - start < 3, opened == nil {
                if notch.state == .open { opened = CACurrentMediaTime() - start }
                try? await Task.sleep(for: .milliseconds(5))
            }
            log("Reduce Motion: release → open \(ms(opened)) ms, overlay \(overlay.isVisible ? "still up FAIL" : "gone OK")")
            await waitForInsert(capture, web: web, count: 1)
            capture.debugReduceMotion = nil
            notch.close()
            _ = await notch.waitForRest()

            await realFreeze(notch: notch, panel: panel, screen: screen)
            finish(clipboard)
        }
    }

    /// `-captureorient <dir>`: a short stroke near the top-left corner; is it drawn where the pointer
    /// went (top-left), or mirrored?
    static func orientation(panel: NotchPanel, notch: NotchViewModel, dir: URL) {
        self.dir = dir
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let capture = notch.capture, let screen = panel.screen else { return finish(PasteboardSnapshot()) }
            let frozen = syntheticFrozen(for: screen)
            capture.debugBegin(on: screen, frozen: frozen, delay: 0.05)
            try? await Task.sleep(for: .milliseconds(400))
            let overlay = capture.debugPanel
            let stroke = (0...100).map { CGPoint(x: 300 + CGFloat($0) * 3, y: 200 + CGFloat($0) * 0.5) }
            send(.leftMouseDown, stroke[0], to: overlay)
            for point in stroke.dropFirst() { send(.leftMouseDragged, point, to: overlay) }
            try? await Task.sleep(for: .milliseconds(300))
            if let image = DebugImages.window(overlay) {
                DebugImages.write(image, dir, "orient")
                let scale = CGFloat(image.width) / screen.frame.width
                let at = pixel(image, at: CGPoint(x: 450 * scale, y: 225 * scale))
                let mirrored = pixel(image, at: CGPoint(x: 450 * scale, y: (screen.frame.height - 225) * scale))
                log("stroke where the pointer went (450, 225): \(at); mirrored (450, \(Int(screen.frame.height - 225))): \(mirrored) → \(min(at.r, at.g, at.b) > 200 ? "OK" : min(mirrored.r, mirrored.g, mirrored.b) > 200 ? "FLIPPED" : "neither")")
            }
            if let image = DebugImages.window(overlay) {
                let scale = CGFloat(image.width) / screen.frame.width
                let marker = pixel(image, at: CGPoint(x: 60 * scale, y: 60 * scale))
                log("frozen picture upright (red marker top-left): \(marker) \(marker.r > 150 && marker.g < 60 ? "OK" : "FAIL")")
            }
            send(.leftMouseUp, stroke.last!, to: overlay)
            let look = CaptureLook.full
            try? await Task.sleep(for: .seconds(look.morph * 1.3))
            if let image = DebugImages.window(overlay) {
                DebugImages.write(image, dir, "orient-lift")
                // Inside the selection, over the synthetic window (light) just below the stroke.
                let scale = CGFloat(image.width) / screen.frame.width
                let inside = pixel(image, at: CGPoint(x: 450 * scale, y: 254 * scale))
                let outside = pixel(image, at: CGPoint(x: 450 * scale, y: 300 * scale))
                log("lifted selection shows the window, undimmed \(inside); window outside it, dimmed \(outside) → \(inside.r > outside.r + 40 ? "OK" : "FAIL")")
            }
            try? await Task.sleep(for: .seconds(look.hold + look.flight * 0.6))
            if let image = DebugImages.window(overlay) { DebugImages.write(image, dir, "orient-flight") }
            try? await Task.sleep(for: .seconds(2))
            notch.close()
            _ = await notch.waitForRest()
            finish(PasteboardSnapshot())
        }
    }

    // MARK: Steps

    /// Capture mode with the synthetic picture, `points` drawn (a click if they're close), released.
    private static func captureOnce(_ capture: CaptureViewModel, screen: NSScreen, frozen: FrozenScreen,
                                    overlay: CaptureOverlayPanel, notch: NotchViewModel, points: [CGPoint]) async {
        capture.debugBegin(on: screen, frozen: frozen, delay: 0.05)
        try? await Task.sleep(for: .milliseconds(250))
        send(.leftMouseDown, points[0], to: overlay)
        for point in points.dropFirst() { send(.leftMouseDragged, point, to: overlay) }
        send(.leftMouseUp, points.last!, to: overlay)
    }

    private static func escapes(capture: CaptureViewModel, screen: NSScreen, frozen: FrozenScreen,
                                overlay: CaptureOverlayPanel, notch: NotchViewModel, web: WKWebView) async {
        let before = await receivedImages(web).count
        let stroke = (0..<80).map { CGPoint(x: 400 + CGFloat($0) * 4, y: 300 + 60 * sin(CGFloat($0) / 8)) }
        let look = CaptureLook.full
        // (stage, how long after the release — nil: before it).
        let stages: [(String, Double?, Double)] = [("freezing", nil, 0.1), ("drawing", nil, 0.4),
                                                   ("selecting", 0.1, 0), ("flying", look.morph * 1.4 + look.hold + look.flight * 0.3, 0)]
        for (name, afterRelease, beforeDrawing) in stages {
            capture.debugBegin(on: screen, frozen: frozen, delay: name == "freezing" ? 1.0 : 0.05)
            try? await Task.sleep(for: .seconds(beforeDrawing))
            var phase = capture.phase
            if name != "freezing" {
                send(.leftMouseDown, stroke[0], to: overlay)
                for point in stroke.dropFirst() { send(.leftMouseDragged, point, to: overlay) }
                if let afterRelease {
                    send(.leftMouseUp, stroke.last!, to: overlay)
                    try? await Task.sleep(for: .seconds(afterRelease))
                }
                phase = capture.phase
            }
            send(.keyDown, .zero, to: overlay)
            try? await Task.sleep(for: .seconds(0.6))
            let clean = !overlay.isVisible && capture.phase == .idle && notch.state != .open && capture.pending == nil
            log("Esc while \(name) (phase was \(phase)): overlay \(overlay.isVisible ? "up" : "gone"), phase \(capture.phase), notch \(notch.state) \(clean ? "OK" : "FAIL")")
        }
        try? await Task.sleep(for: .seconds(1))
        log("nothing reached the page after the Escs: \(await receivedImages(web).count == before ? "OK" : "FAIL")")
    }

    /// The band on each tab, and the chip, for looking at.
    private static func bandShots(notch: NotchViewModel, panel: NotchPanel, capture: CaptureViewModel) async {
        notch.open()
        _ = await notch.waitForRest()
        for tab in PanelTab.allCases {
            notch.select(tab)
            _ = await notch.waitForRest()
            try? await Task.sleep(for: .milliseconds(500))
            if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "0-band-\(tab)") }
        }
        notch.select(.terminal)
        notch.close()
        _ = await notch.waitForRest()
    }

    /// With DEXMA's Screen Recording grant: real freezes, timed, and the open panel left out.
    private static func realFreeze(notch: NotchViewModel, panel: NotchPanel, screen: NSScreen) async {
        guard CGPreflightScreenCaptureAccess() else {
            log("real freeze: skipped (no Screen Recording grant; launch with `open` to use DEXMA's)")
            return
        }
        for run in 1...3 {
            let t0 = CACurrentMediaTime()
            guard let frozen = try? await ScreenFreezer.freeze(screen) else {
                log("real freeze \(run): FAIL")
                continue
            }
            log("real freeze \(run): \(ms(CACurrentMediaTime() - t0)) ms, \(frozen.image.width)×\(frozen.image.height) px for \(Int(frozen.size.width))×\(Int(frozen.size.height)) pt, \(frozen.windows.count) windows")
        }
        for other in NSScreen.screens {
            let frozen = try? await ScreenFreezer.freeze(other)
            log("windows click-to-capture can pick on \(other.localizedName) (\(Int(other.frame.width))×\(Int(other.frame.height)) pt): \(frozen?.windows.count ?? -1), frontmost \(frozen?.windows.first.map { "\($0)" } ?? "none")")
        }
        notch.open()
        _ = await notch.waitForRest()
        let withPanel = await DebugImages.screen(around: panel)
        let frozen = try? await ScreenFreezer.freeze(screen)
        notch.close()
        _ = await notch.waitForRest()
        guard let withPanel, let frozen else {
            log("exclusion check: FAIL (no pictures)")
            return
        }
        // The card's middle: black (the panel) in the screen as it is, whatever is behind in the freeze.
        let card = notch.geometry.contentFrame
        let scale = screen.backingScaleFactor
        let inPanel = CGPoint(x: card.midX * scale, y: card.midY * scale)
        let onScreen = CGPoint(x: (panel.frame.minX - screen.frame.minX + card.midX) * scale,
                               y: (screen.frame.maxY - panel.frame.maxY + card.midY) * scale)
        let a = pixel(withPanel, at: inPanel), b = pixel(frozen.image, at: onScreen)
        log("exclusion: card centre with DEXMA \(a), in the freeze \(b) \(a != b ? "OK (the panel isn't in the freeze)" : "CHECK (same colour: the screen behind may be black)")")
    }

    // MARK: The stand-in page

    /// A stand-in for claude.ai's composer (TipTap editor `chat-input`, file input `file-upload`),
    /// served as claude.ai so the attacher treats it as the real site. It records every file it
    /// takes (how, size, pixel size). Modes: normal; noPaste (the editor ignores pasted files);
    /// login (the sign-in page: no composer).
    private static func loadStandIn(_ web: WKWebView, mode: String) async {
        let composer = mode == "login" ? "<input type=email data-testid=email placeholder=Email>" : """
            <div id=files></div>
            <div class="tiptap ProseMirror" contenteditable="true" data-testid="chat-input" style="min-height:24px;outline:none"></div>
            <input type=file data-testid="file-upload" accept=".png,.jpg" multiple style="display:none">
            """
        let html = """
            <html><body style="background:#262624;color:#eee;font:14px -apple-system">
            <div style="margin:40px;border:1px solid #555;border-radius:12px;padding:12px">\(composer)</div>
            <script>
            window.__received = [];
            function attach(file, how) {
              var img = document.createElement('img'); img.setAttribute('data-testid', 'file-thumbnail'); img.style.height = '48px';
              img.src = URL.createObjectURL(file); document.getElementById('files').appendChild(img);
              createImageBitmap(file).then(function (b) { window.__received.push(how + ' ' + file.type + ' ' + file.size + ' B ' + b.width + '×' + b.height); });
            }
            var editor = document.querySelector('[data-testid=chat-input]');
            if (editor) editor.addEventListener('paste', function (e) {
              if ('\(mode)' === 'noPaste') return;
              var f = e.clipboardData.files;
              if (f.length) { e.preventDefault(); for (var i = 0; i < f.length; i++) attach(f[i], e.isTrusted ? 'trusted-paste' : 'scripted-paste'); }
            });
            var input = document.querySelector('[data-testid=file-upload]');
            if (input) input.addEventListener('change', function () { for (var i = 0; i < this.files.length; i++) attach(this.files[i], 'file-input'); });
            </script></body></html>
            """
        let path = mode == "login" ? "login" : "new"
        web.loadHTMLString(html, baseURL: URL(string: "https://claude.ai/\(path)"))
        let end = CACurrentMediaTime() + 5
        try? await Task.sleep(for: .milliseconds(100))
        while web.isLoading, CACurrentMediaTime() < end { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private static func receivedImages(_ web: WKWebView) async -> [String] {
        (try? await web.evaluateJavaScript("window.__received || []") as? [String]) ?? []
    }

    /// Waits for the capture to be in the page and the attacher done; how it went in.
    @discardableResult
    private static func waitForInsert(_ capture: CaptureViewModel, web: WKWebView, count: Int) async -> ClaudeInsertMethod? {
        let end = CACurrentMediaTime() + 8
        while CACurrentMediaTime() < end {
            if await receivedImages(web).count >= count, capture.pending == nil, let method = capture.lastMethod {
                capture.debugForgetLastMethod()
                return method
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    // MARK: Pointer

    /// Sends one move per display frame (like a real drag), timing each and the frames.
    private static func drive(_ points: [CGPoint], on overlay: CaptureOverlayPanel) async
        -> (seconds: Double, p50: Double, p95: Double, max: Double, late: Int, frames: Int) {
        send(.leftMouseDown, points[0], to: overlay)
        let ticker = Ticker()
        var costs: [Double] = []
        var stamps: [CFTimeInterval] = []
        var index = 1
        let start = CACurrentMediaTime()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            ticker.start(on: overlay) { stamp in
                stamps.append(stamp)
                guard index < points.count else {
                    ticker.stop()
                    done.resume()
                    return
                }
                let t0 = CACurrentMediaTime()
                send(.leftMouseDragged, points[index], to: overlay)
                costs.append((CACurrentMediaTime() - t0) * 1000)
                index += 1
            }
        }
        let interval = zip(stamps, stamps.dropFirst()).map { $1 - $0 }.sorted()[max(stamps.count / 2 - 1, 0)]
        let late = zip(stamps, stamps.dropFirst()).filter { $1 - $0 > interval * 1.5 }.count
        let sorted = costs.sorted()
        return (CACurrentMediaTime() - start, sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)],
                sorted.last ?? 0, late, stamps.count)
    }

    private static func send(_ type: NSEvent.EventType, _ point: CGPoint, to window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let event: NSEvent?
        if type == .keyDown {
            event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                     charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
        } else {
            event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                       pressure: type == .leftMouseUp ? 0 : 1)
        }
        if let event { window.sendEvent(event) }
    }

    // MARK: Pictures

    /// A display-sized picture: dark gradient, a 100 pt grid, a red square in the top-left corner
    /// (orientation), small text (crop sharpness), and one "window" at (300, 250, 500 × 320).
    private static func syntheticFrozen(for screen: NSScreen) -> FrozenScreen {
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        // Top-left origin, in points.
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(CGColor(red: 0.16, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.15))
        for x in stride(from: 0, to: size.width, by: 100) { context.stroke(CGRect(x: x, y: 0, width: 0, height: size.height)) }
        for y in stride(from: 0, to: size.height, by: 100) { context.stroke(CGRect(x: 0, y: y, width: size.width, height: 0)) }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 300, y: 250, width: 500, height: 320))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        ("A window. Small text for checking the crop's sharpness." as NSString)
            .draw(at: CGPoint(x: 316, y: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
        ("Draw to ask — capture test" as NSString)
            .draw(at: CGPoint(x: size.width / 2 - 120, y: size.height / 2), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return FrozenScreen(image: context.makeImage()!, size: size, windows: [CGRect(x: 300, y: 250, width: 500, height: 320)])
    }

    private static func pixel(_ image: CGImage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // The pixel at `point` (top-left origin) lands on the 1 × 1 context.
        context?.draw(image, in: CGRect(x: -point.x.rounded(.down), y: -(CGFloat(image.height) - point.y.rounded(.down) - 1),
                                        width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    /// WindowServer's CPU time so far (it composites and strokes the overlay's layers).
    private static func windowServerSeconds() -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "ps -o time= -p $(pgrep -x WindowServer | head -1)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
            .reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    // MARK: Output

    private static func ms(_ seconds: CFTimeInterval?) -> String {
        seconds.map { String(format: "%.0f", $0 * 1000) } ?? "—"
    }

    private static func log(_ line: String) {
        print("[capture] \(line)")
        report.append(line)
    }

    private static func finish(_ clipboard: PasteboardSnapshot) {
        clipboard.restore()
        try? report.joined(separator: "\n").write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}

/// A display link on a window, calling back once per frame with its timestamp.
private final class Ticker: NSObject {
    private var link: CADisplayLink?
    private var tick: ((CFTimeInterval) -> Void)?

    func start(on window: NSWindow, tick: @escaping (CFTimeInterval) -> Void) {
        self.tick = tick
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        tick?(link.timestamp)
    }
}
#endif
