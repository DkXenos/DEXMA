#if DEBUG
import AppKit
import WebKit

/// Debug-only: `DEXMA -claudeprobe <dir>` checks the Claude tab against the real claude.ai
/// (network needed, no sign-in): does it load (or stop at a challenge), what "Continue with
/// Google" does inside the tab, whether the email sign-in form is usable (nothing is
/// submitted), and whether a pasted image reaches a page and which drag types the web view
/// accepts. Prints `[claude] …` lines, then quits.
enum ClaudeProbe {
    static func run(panel: NotchPanel, notch: NotchViewModel, dir: URL) {
        Task { @MainActor in
            let web = notch.claude.session
            let view = web.webView
            print("[claude] launch load requested: \(web.configuration.home?.absoluteString ?? "-")")
            await waitForLoad(view, seconds: 25)
            await describe("after launch", view)

            view.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
            await waitForLoad(view, seconds: 20)
            try? await Task.sleep(for: .seconds(2))
            await describe("login page", view)
            let buttons = try? await view.evaluateJavaScript("""
                Array.from(document.querySelectorAll('button, a')).map(b => (b.innerText || '').trim())
                  .filter(t => t.length > 0 && t.length < 60).slice(0, 25).join(' | ')
                """) as? String
            print("[claude] login buttons/links: \(buttons ?? "-")")
            let email = try? await view.evaluateJavaScript("""
                (function(){ var e = document.querySelector('input[type=email], input[name=email], #email');
                  if (!e) return 'no email field';
                  e.focus(); return 'email field: ' + (e.getAttribute('placeholder') || e.name || e.id) +
                    ', focusable ' + (document.activeElement === e); })()
                """) as? String
            print("[claude] \(email ?? "-")")

            // Continue with Google: click it and watch where it goes (tab or popup).
            let clicked = try? await view.evaluateJavaScript("""
                (function(){ var b = Array.from(document.querySelectorAll('button, a'))
                  .find(x => /google/i.test(x.innerText || x.getAttribute('aria-label') || ''));
                  if (!b) return 'no Google button'; b.click(); return 'clicked: ' + b.innerText.trim(); })()
                """) as? String
            print("[claude] \(clicked ?? "-")")
            try? await Task.sleep(for: .seconds(6))
            print("[claude] after Google click — tab URL: \(view.url?.absoluteString ?? "-")")
            for (index, popup) in web.debugPopupWebViews.enumerated() {
                await waitForLoad(popup, seconds: 10)
                await describe("popup \(index)", popup)
            }
            if web.debugPopupWebViews.isEmpty, view.url?.host?.contains("google") == true {
                await describe("Google page in the tab", view)
            }

            // Pasting an image into a page through the panel's ⌘V path (pasteboard restored).
            await pasteCheck(panel: panel, view: view)
            let types = view.registeredDraggedTypes.map(\.rawValue)
            let wantedTypes = ["public.file-url", "public.png", "public.tiff", "NSFilenamesPboardType"]
            print("[claude] drag types accepted by the web view: \(wantedTypes.filter { types.contains($0) }) (of \(types.count))")
            NSApp.terminate(nil)
        }
    }

    private static func pasteCheck(panel: NotchPanel, view: WKWebView) async {
        view.loadHTMLString("""
            <html><body><div id=box contenteditable style="width:300px;height:100px">x</div><script>
            window.result = 'nothing pasted';
            document.getElementById('box').addEventListener('paste', function (e) {
              var items = Array.from(e.clipboardData.items).map(i => i.kind + ':' + i.type);
              var files = e.clipboardData.files.length;
              window.result = 'paste event: files=' + files + ' items=' + items.join(',');
            });
            </script></body></html>
            """, baseURL: URL(string: "https://claude.ai/"))
        await waitForLoad(view, seconds: 5)
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        let image = NSImage(size: CGSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        board.clearContents()
        board.writeObjects([image])
        panel.allowsKey = true
        panel.makeKey()
        panel.makeFirstResponder(view)
        _ = try? await view.evaluateJavaScript("document.getElementById('box').focus()")
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: panel)
        try? await Task.sleep(for: .seconds(1))
        let result = try? await view.evaluateJavaScript("window.result") as? String
        print("[claude] image paste through ⌘V's path: \(result ?? "-") (first responder \(panel.firstResponder.map { "\(type(of: $0))" } ?? "nil"))")
        board.clearContents()
        if !saved.isEmpty { board.writeObjects(saved) }
        panel.allowsKey = false
    }

    private static func describe(_ label: String, _ view: WKWebView) async {
        let title = (try? await view.evaluateJavaScript("document.title") as? String) ?? "-"
        let text = (try? await view.evaluateJavaScript(
            "(document.body ? document.body.innerText : '').replace(/\\s+/g, ' ').slice(0, 300)") as? String) ?? "-"
        print("[claude] \(label): url \(view.url?.absoluteString ?? "-") | title \(title) | text: \(text)")
    }

    private static func waitForLoad(_ view: WKWebView, seconds: Double) async {
        let end = CACurrentMediaTime() + seconds
        try? await Task.sleep(for: .milliseconds(300))
        while CACurrentMediaTime() < end, view.isLoading || view.url == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
#endif
