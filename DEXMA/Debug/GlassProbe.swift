#if DEBUG
import AppKit
import WebKit

/// Debug-only: `DEXMA -glassprobe <dir>` reads claude.ai's page in the Claude tab (nothing is
/// typed or sent): signed in or not, the composer and its ancestors, the send button, the theme
/// variables, and which elements paint large opaque backgrounds (what the see-through stylesheet
/// has to clear). Prints `[probe] …` lines and a picture of the page, then quits.
enum GlassProbe {
    static func run(notch: NotchViewModel, dir: URL) {
        Task { @MainActor in
            let view = notch.claude.session.webView
            let end = CACurrentMediaTime() + 30
            try? await Task.sleep(for: .seconds(1))
            while CACurrentMediaTime() < end, view.isLoading || view.url == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .seconds(4))
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-probeurl"), index + 1 < arguments.count,
               let url = URL(string: arguments[index + 1]) {
                view.load(URLRequest(url: url))
                try? await Task.sleep(for: .seconds(6))
            }
            if arguments.contains("-cleardraft") {
                // A test's text left as claude.ai's saved draft: emptied, saved, reloaded.
                _ = try? await view.evaluateJavaScript("""
                    (function(){var e=document.querySelector('[data-testid="chat-input"]'); if(!e) return;
                     e.focus(); document.execCommand('selectAll'); document.execCommand('delete');})()
                    """)
                try? await Task.sleep(for: .seconds(3))
                view.reload()
                try? await Task.sleep(for: .seconds(6))
                let left = try? await view.evaluateJavaScript(
                    "(document.querySelector('[data-testid=\"chat-input\"]')||{}).innerText") as? String
                print("[probe] draft after clearing: '\((left ?? "-").trimmingCharacters(in: .whitespacesAndNewlines))'")
            }
            print("[probe] url \(view.url?.absoluteString ?? "-")")
            for (label, script) in scripts {
                let result = try? await view.evaluateJavaScript(script)
                print("[probe] \(label): \(result.map { "\($0)" } ?? "-")")
            }
            if ProcessInfo.processInfo.arguments.contains("-inserttest") { await insertTests(notch: notch, view: view) }
            let configuration = WKSnapshotConfiguration()
            if let image = try? await view.takeSnapshot(configuration: configuration),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                DebugImages.write(cgImage, dir, "claude-page")
            }
            NSApp.terminate(nil)
        }
    }

    /// Which way of putting text into the composer ProseMirror takes (cleared after each; never sent).
    private static func insertTests(notch: NotchViewModel, view: WKWebView) async {
        let text = "line one\nline two"
        let read = "(function(){var e=document.querySelector('[data-testid=\"chat-input\"]');return e?JSON.stringify(e.innerText):'none';})()"
        let clear = """
            (function(){var e=document.querySelector('[data-testid="chat-input"]');e.focus();
             document.execCommand('selectAll');document.execCommand('delete');return e.innerText.length;})()
            """
        let focus = "document.querySelector('[data-testid=\"chat-input\"]').focus()"
        _ = try? await view.callAsyncJavaScript("""
            var e=document.querySelector('[data-testid="chat-input"]'); e.focus();
            var lines=text.split('\\n');
            lines.forEach(function(l,i){ if(i>0) document.execCommand('insertParagraph'); document.execCommand('insertText', false, l); });
            """, arguments: ["text": text], contentWorld: .page)
        try? await Task.sleep(for: .milliseconds(300))
        print("[probe] A execCommand: \((try? await view.evaluateJavaScript(read)) ?? "-")")
        print("[probe]   cleared → \((try? await view.evaluateJavaScript(clear)) ?? "-")")
        _ = try? await view.callAsyncJavaScript("""
            var e=document.querySelector('[data-testid="chat-input"]'); e.focus();
            var dt=new DataTransfer(); dt.setData('text/plain', text);
            var ev=new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:dt});
            e.dispatchEvent(ev); return ev.defaultPrevented;
            """, arguments: ["text": text], contentWorld: .page)
        try? await Task.sleep(for: .milliseconds(300))
        print("[probe] B synthetic paste: \((try? await view.evaluateJavaScript(read)) ?? "-")")
        print("[probe]   cleared → \((try? await view.evaluateJavaScript(clear)) ?? "-")")
        let window = view.window
        (window as? NotchPanel)?.allowsKey = true
        window?.makeKey()
        window?.makeFirstResponder(view)
        _ = try? await view.evaluateJavaScript(focus)
        let parts = text.components(separatedBy: "\n")
        for (i, part) in parts.enumerated() {
            if i > 0 { view.doCommand(by: #selector(NSResponder.insertLineBreak(_:))) }
            view.insertText(part)
        }
        try? await Task.sleep(for: .milliseconds(300))
        print("[probe] C native insertText (key \(window?.isKeyWindow ?? false)): \((try? await view.evaluateJavaScript(read)) ?? "-")")
        print("[probe]   cleared → \((try? await view.evaluateJavaScript(clear)) ?? "-")")
        (window as? NotchPanel)?.allowsKey = false
    }

    private static let scripts: [(String, String)] = [
        ("title", "document.title"),
        ("composer chain", """
            (function () {
              var el = document.querySelector('[data-testid="chat-input"]')
                || document.querySelector('div.ProseMirror[contenteditable="true"]');
              if (!el) return 'no composer';
              var out = [];
              for (var n = el; n && n !== document.documentElement; n = n.parentElement) {
                var s = getComputedStyle(n), r = n.getBoundingClientRect();
                out.push(n.tagName + (n.id ? '#' + n.id : '') + (n.dataset.testid ? '[' + n.dataset.testid + ']' : '')
                  + ' .' + (typeof n.className === 'string' ? n.className.slice(0, 140) : '')
                  + ' {pos ' + s.position + ', bg ' + s.backgroundColor + ', ' + Math.round(r.width) + 'x'
                  + Math.round(r.height) + ' @' + Math.round(r.top) + '}');
              }
              return '\\n  ' + out.join('\\n  ');
            })()
            """),
        ("buttons near composer", """
            (function () {
              return Array.from(document.querySelectorAll('button')).filter(function (b) {
                return b.closest('fieldset') || /send/i.test(b.getAttribute('aria-label') || '');
              }).map(function (b) {
                return (b.getAttribute('aria-label') || b.innerText.trim().slice(0, 20)) + (b.dataset.testid ? '[' + b.dataset.testid + ']' : '')
                  + (b.disabled ? ' (disabled)' : '');
              }).join(' | ');
            })()
            """),
        ("large backgrounds", """
            (function () {
              var vw = innerWidth, vh = innerHeight, out = [];
              document.querySelectorAll('*').forEach(function (n) {
                var s = getComputedStyle(n);
                if (s.backgroundColor === 'rgba(0, 0, 0, 0)' && s.backgroundImage === 'none') return;
                var r = n.getBoundingClientRect();
                if (r.width * r.height < vw * vh * 0.04) return;
                out.push(n.tagName + (n.dataset.testid ? '[' + n.dataset.testid + ']' : '') + ' .'
                  + (typeof n.className === 'string' ? n.className.slice(0, 120) : '') + ' bg ' + s.backgroundColor
                  + (s.backgroundImage !== 'none' ? ' img ' + s.backgroundImage.slice(0, 60) : '')
                  + ' ' + Math.round(r.width) + 'x' + Math.round(r.height));
              });
              return out.length + '\\n  ' + out.slice(0, 40).join('\\n  ');
            })()
            """),
        ("theme vars", """
            (function () {
              var names = {};
              for (var i = 0; i < document.styleSheets.length; i++) {
                var rules; try { rules = document.styleSheets[i].cssRules; } catch (e) { continue; }
                for (var j = 0; j < rules.length; j++) {
                  var t = rules[j].cssText || '';
                  var m = t.match(/--bg-[a-z0-9-]+/g);
                  if (m) m.forEach(function (x) { names[x] = 1; });
                }
              }
              var s = getComputedStyle(document.documentElement);
              return Object.keys(names).slice(0, 30).map(function (k) { return k + '=' + s.getPropertyValue(k).trim(); }).join(', ')
                + ' | html class: ' + document.documentElement.className + ' | data-theme: '
                + document.documentElement.getAttribute('data-theme') + ' | mode: ' + document.documentElement.dataset.mode;
            })()
            """),
        ("stack at the top bar", """
            (function () {
              return '\\n  ' + document.elementsFromPoint(200, 20).map(function (n) {
                var s = getComputedStyle(n);
                return n.tagName + (n.dataset.testid ? '[' + n.dataset.testid + ']' : '') + ' .'
                  + (typeof n.className === 'string' ? n.className.slice(0, 150) : '') + ' {bg ' + s.backgroundColor
                  + (s.backgroundImage !== 'none' ? ', img ' + s.backgroundImage.slice(0, 80) : '')
                  + (s.backdropFilter && s.backdropFilter !== 'none' ? ', backdrop ' + s.backdropFilter : '')
                  + ', pos ' + s.position + '}';
              }).join('\\n  ');
            })()
            """),
        ("title row", """
            (function () {
              var out = [];
              document.querySelectorAll('[class*="title-row"]').forEach(function (n) {
                var r = n.getBoundingClientRect();
                [null, '::before', '::after'].forEach(function (p) {
                  var s = getComputedStyle(n, p);
                  out.push(n.tagName + (p || '') + ' .' + (typeof n.className === 'string' ? n.className.slice(0, 160) : '')
                    + ' {bg ' + s.backgroundColor + (s.backgroundImage !== 'none' ? ', img ' + s.backgroundImage.slice(0, 120) : '')
                    + ', mask ' + (s.maskImage || s.webkitMaskImage || '').slice(0, 60) + ', display ' + s.display
                    + ', ' + Math.round(r.width) + 'x' + Math.round(r.height) + ' @' + Math.round(r.top)
                    + ', attrs ' + Array.from(n.attributes).map(function (a) { return a.name; }).filter(function (a) { return a.indexOf('data-') === 0; }).join(' ') + '}');
                });
              });
              return '\\n  ' + out.join('\\n  ');
            })()
            """),
        ("messages", """
            (function () {
              return 'user ' + document.querySelectorAll('[data-testid="user-message"]').length
                + ', claude ' + document.querySelectorAll('.font-claude-message, [data-is-streaming]').length;
            })()
            """),
    ]
}
#endif
