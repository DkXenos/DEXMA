import AppKit
import os
import WebKit

/// claude.ai's composer, driven from the floating glass's own field, through scripts in the page:
/// - the page style: backgrounds cleared so the glass card shows through (see-through), and
///   claude.ai's own composer moved out of sight while the native field works (it stays laid out
///   and focusable, so text and pictures still go into it);
/// - typing the question in, sending it and checking that it went;
/// - showing claude.ai's composer again when that path fails (the text goes there instead).
/// Selectors are claude.ai's (2026-10-05: `chat-input` is TipTap/ProseMirror in a fieldset,
/// `chat-input-send` the send button), with generic fallbacks.
final class ClaudeComposer {
    enum SendResult: Equatable {
        case sent
        /// The message box wasn't there (signed out, still loading, the page changed).
        case noComposer
        /// The text didn't go in as typed.
        case textRejected
        /// The send button never became usable, or nothing was sent after clicking it.
        case notSent
    }

    private static let logger = Logger(category: "Glass")
    private let tab: WebTab
    let attacher: ClaudeAttacher
    private var webView: WKWebView { tab.webView }

    init(tab: WebTab) {
        self.tab = tab
        attacher = ClaudeAttacher(tab: tab)
    }

    // MARK: Page style

    /// The style for every page (installed as the tab's page script while Claude is in glass):
    /// `clear` makes the page's own backgrounds transparent, `native` hides claude.ai's composer.
    static func pageScript(clear: Bool, native: Bool) -> String {
        "window.__dexmaGlass = { clear: \(clear), native: \(native) };\n" + styleScript
    }

    /// The same, on the page that's showing now (no reload).
    func apply(clear: Bool, native: Bool) {
        webView.evaluateJavaScript("window.__dexmaGlass = { clear: \(clear), native: \(native) };"
                                   + " window.__dexmaApply && window.__dexmaApply();") { _, _ in }
    }

    /// Tags (data attributes, which the stylesheet targets) are found again as the page changes:
    /// the composer's fieldset and its sticky dock; with `clear`, every element painting a large
    /// background behind the conversation or a bar across its top (not menus, dialogs, code or
    /// the composer). The top bar's backdrop (`df-header-backdrop`, 2026-10-05) is cleared by name.
    private static let styleScript = """
        (function () {
          if (window.__dexmaApply) { window.__dexmaApply(); return; }
          var css = [
            'html[data-dexma-clear], html[data-dexma-clear] body, html[data-dexma-clear] [data-dexma-plain],',
            'html[data-dexma-clear] .df-header-backdrop, html[data-dexma-clear] .df-header-peek-cover {',
            '  background-color: transparent !important; background-image: none !important; }',
            'html[data-dexma-native] [data-dexma-composer] { position: fixed !important; left: -10000px !important;',
            '  top: 0 !important; width: 600px !important; opacity: 0 !important; pointer-events: none !important; }',
            'html[data-dexma-native] [data-dexma-dock] { background: transparent !important; padding-bottom: 0 !important;',
            '  min-height: 0 !important; }'
          ].join('\\n');
          var scheduled = false;
          function set(el, name, on) { if (on) el.setAttribute(name, ''); else el.removeAttribute(name); }
          function composer() {
            return document.querySelector('[data-testid="chat-input"]')
              || document.querySelector('div.ProseMirror[contenteditable="true"]');
          }
          function tag() {
            var state = window.__dexmaGlass || {};
            var editor = composer();
            if (editor) {
              var box = editor.closest('fieldset') || editor.parentElement;
              if (box && !box.hasAttribute('data-dexma-composer')) {
                document.querySelectorAll('[data-dexma-composer]').forEach(function (n) { n.removeAttribute('data-dexma-composer'); });
                box.setAttribute('data-dexma-composer', '');
              }
              for (var n = box && box.parentElement; n && n !== document.body; n = n.parentElement) {
                if (getComputedStyle(n).position === 'sticky') { n.setAttribute('data-dexma-dock', ''); break; }
              }
            }
            if (!state.clear) return;
            var vw = innerWidth, vh = innerHeight;
            document.querySelectorAll('[class*="bg-"], main, header, nav').forEach(function (n) {
              if (n.hasAttribute('data-dexma-plain')) return;
              if (n.closest('[role=dialog], [role=menu], [role=listbox], [role=tooltip], [data-radix-popper-content-wrapper], pre, [data-dexma-composer]')) return;
              var s = getComputedStyle(n);
              if (s.backgroundColor === 'rgba(0, 0, 0, 0)' && s.backgroundImage === 'none') return;
              var r = n.getBoundingClientRect();
              var wide = r.width >= vw * 0.6;
              var tall = r.height >= vh * 0.4;
              // Sticky or fixed bars, and the backdrops pinned behind the top bar.
              var bar = (s.position === 'sticky' || s.position === 'fixed' || r.top < 8) && r.height < vh * 0.4;
              if (wide && (tall || bar)) n.setAttribute('data-dexma-plain', '');
            });
          }
          function apply() {
            var root = document.documentElement;
            if (!root) return;
            var state = window.__dexmaGlass || {};
            set(root, 'data-dexma-clear', !!state.clear);
            set(root, 'data-dexma-native', !!state.native);
            if (!document.getElementById('dexma-glass-style') && (document.head || document.body)) {
              var style = document.createElement('style');
              style.id = 'dexma-glass-style';
              style.textContent = css;
              (document.head || document.body).appendChild(style);
            }
            tag();
          }
          function later() {
            if (scheduled) return;
            scheduled = true;
            setTimeout(function () { scheduled = false; apply(); }, 400);
          }
          window.__dexmaApply = apply;
          // While hidden, the composer can't take focus by itself (claude.ai focuses it whenever the
          // window becomes key: what was typed went there, and Return sent it without DEXMA's
          // picture). DEXMA's own scripts allow it while they work (__dexmaFocusOK).
          document.addEventListener('focusin', function (e) {
            var state = window.__dexmaGlass || {};
            if (!state.native || window.__dexmaFocusOK) return;
            var box = document.querySelector('[data-dexma-composer]');
            if (box && box.contains(e.target) && e.target.blur) e.target.blur();
          }, true);
          new MutationObserver(later).observe(document, { childList: true, subtree: true });
          addEventListener('resize', later);
          addEventListener('DOMContentLoaded', apply);
          apply();
        })();
        """

    /// DEXMA's scripts may focus the hidden composer (for a paste or typing), or not any more.
    func allowComposerFocus(_ allowed: Bool) async {
        _ = try? await webView.evaluateJavaScript("window.__dexmaFocusOK = \(allowed);")
    }

    // MARK: Sending

    /// Types `text` into the message box (replacing any draft) and sends it, with whatever is
    /// attached. Checks it really went: the box empties and a new message (or conversation) appears.
    func send(_ text: String) async -> SendResult {
        guard await attacher.composerState() == .ready else { return .noComposer }
        let before = await messageCount()
        let path = webView.url?.path
        if !text.isEmpty {
            guard await insert(text) else { return .textRejected }
        }
        let clicked = try? await webView.callAsyncJavaScript(Self.clickSendScript, arguments: [:], in: nil,
                                                              contentWorld: .page) as? String
        guard clicked == "clicked" else {
            Self.logger.error("Send button: \(clicked ?? "-", privacy: .public)")
            return .notSent
        }
        let deadline = CACurrentMediaTime() + 8
        while CACurrentMediaTime() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            let empty = await editorText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if empty, await messageCount() > before || webView.url?.path != path {
                Self.logger.notice("Sent from the glass field")
                return .sent
            }
        }
        return .notSent
    }

    /// Replaces the draft with `text` (lines as paragraphs): through the editor's own editing
    /// commands, else a paste of the text; true once the box shows exactly it.
    func insert(_ text: String) async -> Bool {
        for script in [Self.insertScript, Self.pasteTextScript] {
            _ = try? await webView.callAsyncJavaScript(script, arguments: ["text": text], in: nil, contentWorld: .page)
            try? await Task.sleep(for: .milliseconds(60))
            if Self.normalized(await editorText()) == Self.normalized(text) { return true }
        }
        Self.logger.error("The text didn't go into claude.ai's message box")
        return false
    }

    /// Whitespace-insensitive, so paragraph markup doesn't count as a difference.
    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func editorText() async -> String {
        (try? await webView.evaluateJavaScript(Self.editorTextScript) as? String) ?? ""
    }

    private func messageCount() async -> Int {
        (try? await webView.evaluateJavaScript(
            "document.querySelectorAll('[data-testid=\"user-message\"]').length") as? Int) ?? 0
    }

    private static let editorTextScript = """
        (function () {
          var e = document.querySelector('[data-testid="chat-input"]')
            || document.querySelector('div.ProseMirror[contenteditable="true"]');
          return e ? e.innerText : '';
        })();
        """

    private static let editorPrelude = """
        window.__dexmaFocusOK = true;
        var editor = document.querySelector('[data-testid="chat-input"]')
          || document.querySelector('div.ProseMirror[contenteditable="true"]');
        if (!editor) return false;
        editor.focus();
        document.execCommand('selectAll');
        document.execCommand('delete');
        """

    private static let insertScript = editorPrelude + """
        text.split('\\n').forEach(function (line, i) {
          if (i > 0) document.execCommand('insertParagraph');
          if (line) document.execCommand('insertText', false, line);
        });
        return true;
        """

    private static let pasteTextScript = editorPrelude + """
        var data = new DataTransfer();
        data.setData('text/plain', text);
        editor.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data }));
        return true;
        """

    /// Waits for the send button to be usable (up to 30 s while it's there but disabled: an
    /// attachment may still be uploading; 2 s if it isn't there at all), then clicks it.
    private static let clickSendScript = """
        function button() {
          return document.querySelector('[data-testid="chat-input-send"]')
            || document.querySelector('button[aria-label="Send message"]');
        }
        var start = Date.now();
        while (Date.now() - start < 30000) {
          var b = button();
          if (b && !b.disabled && b.getAttribute('aria-disabled') !== 'true') { b.click(); return 'clicked'; }
          if (!b && Date.now() - start > 2000) return 'missing';
          await new Promise(function (resolve) { setTimeout(resolve, 150); });
        }
        return button() ? 'disabled' : 'missing';
        """
}
