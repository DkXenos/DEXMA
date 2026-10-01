import AppKit
import os
import WebKit

/// Puts a capture into claude.ai's message box in the Claude tab, then gives the box the caret
/// so the user can type their question. Tried in order, the first that verifiably attaches wins:
/// 1. a real paste (⌘V's path) with the PNG on the clipboard — trusted input, exactly what the
///    composer handles when a user pastes a screenshot; the user's clipboard is put back as soon
///    as the page has taken the image;
/// 2. the composer's file input, given the file through a DataTransfer;
/// 3. a scripted paste, then drop, event carrying the file.
/// Selectors are claude.ai's at the time of writing (`chat-input`, `file-upload`), with generic
/// fallbacks.
final class ClaudeAttacher {
    enum Composer: Equatable {
        case ready
        /// Still loading, or another page of the site.
        case loading
        /// The sign-in page: nothing to attach to until the user signs in.
        case signedOut
    }

    private static let logger = Logger(category: "Capture")
    static let fileName = "DEXMA Capture.png"

    private let tab: WebTab
    private var webView: WKWebView { tab.webView }

    init(tab: WebTab) {
        self.tab = tab
    }

    /// Whether the message box is there to take an attachment.
    func composerState() async -> Composer {
        guard !tab.isLoading else { return .loading }
        let state = try? await webView.evaluateJavaScript(Self.composerStateScript) as? String
        switch state {
        case "ready": return .ready
        case "signedOut": return .signedOut
        default: return .loading
        }
    }

    /// Attaches `image` and focuses the message box. `window` must be key with the tab's page in
    /// it (a paste goes to the first responder). Returns how it went in, nil if nothing worked.
    func insert(_ image: CapturedImage, in window: NSWindow) async -> ClaudeInsertMethod? {
        let before = await attachmentCount()
        var method: ClaudeInsertMethod?
        if await paste(image, in: window, before: before) {
            method = .paste
        } else if await scripted(Self.fileInputScript, image), await attachmentAppeared(after: before) {
            method = .fileInput
        } else if await scripted(Self.syntheticEventScript, image), await attachmentAppeared(after: before) {
            method = .syntheticEvent
        }
        _ = try? await webView.evaluateJavaScript(WebTab.focusComposerScript)
        if let method {
            Self.logger.notice("Capture attached (\(method.rawValue, privacy: .public))")
        } else {
            Self.logger.error("Capture could not be attached")
        }
        return method
    }

    // MARK: Methods

    /// 1. The PNG on the clipboard for a moment and a real paste into the focused message box.
    /// The page reads the clipboard while it handles the paste event, so the user's contents go
    /// back as soon as that event has fired (or after 1.5 s if it never does), and only if the
    /// clipboard still holds ours (nothing else copied meanwhile).
    private func paste(_ image: CapturedImage, in window: NSWindow, before: Int) async -> Bool {
        guard window.isKeyWindow else { return false }
        _ = try? await webView.evaluateJavaScript(Self.pasteWatchScript + WebTab.focusComposerScript)
        window.makeFirstResponder(webView)
        let board = NSPasteboard.general
        let saved = PasteboardSnapshot(board)
        board.clearContents()
        board.setData(image.png, forType: .png)
        let ours = board.changeCount
        NSApp.sendAction(#selector(NSText.paste(_:)), to: webView, from: nil)
        var event: [String: Any]?
        let deadline = CACurrentMediaTime() + 1.5
        while event == nil, CACurrentMediaTime() < deadline {
            try? await Task.sleep(for: .milliseconds(30))
            event = try? await webView.evaluateJavaScript("window.__dexmaPaste || null") as? [String: Any]
        }
        if board.changeCount == ours { saved.restore(to: board) }
        let files = event?["files"] as? Int ?? 0
        let handled = event?["handled"] as? Bool ?? false
        guard files > 0 else { return false }
        if await attachmentAppeared(after: before) { return true }
        // The page took the pasted file (its handler stopped the browser's own paste) even if its
        // attachment markup isn't one this recognises.
        return handled
    }

    /// 2./3.: a script given the PNG (base64) and its file name; true if it found its target.
    private func scripted(_ script: String, _ image: CapturedImage) async -> Bool {
        let arguments: [String: Any] = ["data": image.png.base64EncodedString(), "name": Self.fileName]
        let result = try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
        return result as? Bool ?? false
    }

    /// Attachments in the composer (thumbnails, file cards, their remove buttons).
    private func attachmentCount() async -> Int {
        (try? await webView.evaluateJavaScript(Self.attachmentCountScript) as? Int) ?? 0
    }

    /// Waits up to 3 s for the composer to show one more attachment than `before`.
    private func attachmentAppeared(after before: Int) async -> Bool {
        let deadline = CACurrentMediaTime() + 3
        while CACurrentMediaTime() < deadline {
            if await attachmentCount() > before { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    // MARK: Scripts

    private static let composerStateScript = """
        (function () {
          try {
            if (!/(^|\\.)claude\\.ai$/.test(location.hostname)) return 'loading';
            if (/^\\/(login|logout|magic-link|signup|sso)/.test(location.pathname)) return 'signedOut';
            var el = document.querySelector('[data-testid="chat-input"]')
              || document.querySelector('div.ProseMirror[contenteditable="true"]');
            if (!el) return 'loading';
            var box = el.getBoundingClientRect();
            return box.width > 0 && box.height > 0 ? 'ready' : 'loading';
          } catch (e) { return 'loading'; }
        })();
        """

    /// Records the next paste event: how many files it carried, and (once every handler has run)
    /// whether the page took it over.
    private static let pasteWatchScript = """
        window.__dexmaPaste = null;
        addEventListener('paste', function (e) {
          var files = e.clipboardData ? e.clipboardData.files.length : 0;
          setTimeout(function () { window.__dexmaPaste = { files: files, handled: e.defaultPrevented }; }, 0);
        }, { capture: true, once: true });
        """

    private static let attachmentCountScript = """
        (function () {
          try {
            var editor = document.querySelector('[data-testid="chat-input"]')
              || document.querySelector('div.ProseMirror[contenteditable="true"]');
            if (!editor) return 0;
            var root = editor;
            while (root.parentElement && !root.querySelector('input[type=file]') && root.tagName !== 'FIELDSET'
                   && root.tagName !== 'FORM') root = root.parentElement;
            var found = root.querySelectorAll('img, [data-testid*="thumbnail"], [data-testid*="attachment"], '
              + '[data-testid*="file"]:not(input):not([data-testid="file-upload"]), button[aria-label^="Remove"]');
            var count = 0;
            for (var i = 0; i < found.length; i++) if (!editor.contains(found[i])) count++;
            return count;
          } catch (e) { return 0; }
        })();
        """

    private static let fileScriptPrelude = """
        var bytes = Uint8Array.from(atob(data), function (c) { return c.charCodeAt(0); });
        var transfer = new DataTransfer();
        transfer.items.add(new File([bytes], name, { type: 'image/png' }));
        """

    private static let fileInputScript = fileScriptPrelude + """
        var input = document.querySelector('[data-testid="file-upload"]')
          || Array.from(document.querySelectorAll('input[type=file]'))
               .find(function (i) { return !i.accept || /png|image/.test(i.accept); });
        if (!input) return false;
        input.files = transfer.files;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
        """

    private static let syntheticEventScript = fileScriptPrelude + """
        var editor = document.querySelector('[data-testid="chat-input"]')
          || document.querySelector('div.ProseMirror[contenteditable="true"]');
        if (!editor) return false;
        editor.focus();
        var paste = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: transfer });
        editor.dispatchEvent(paste);
        if (!paste.defaultPrevented) {
          ['dragenter', 'dragover', 'drop'].forEach(function (type) {
            editor.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: transfer }));
          });
        }
        return true;
        """
}
