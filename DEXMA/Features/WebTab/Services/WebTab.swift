import AppKit
import WebKit

/// One web tab (Search or Claude: `WebTabConfiguration`): its long-lived card and web view,
/// created at launch like the shell and never recreated, so the page, its history and scroll
/// position survive closing the panel. Shared by both:
/// - pre-warming (Claude loads its home at launch; Search loads nothing until the first search),
/// - a spare web view for an instant Reset (Search),
/// - dark appearance and no white flash (a fresh web view shows once its first page loaded),
/// - Safari's user agent and the persistent website data store (sign-ins survive restarts),
/// - the card matching the page's background, the swipe-edge and scroll-end detection,
/// - an asynchronous snapshot of the page for the liquid effect (`MotionContent`),
/// - the navigation policy, popups (sign-in windows) and downloads.
final class WebTab: NSObject, MotionContent, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                    NSTextFieldDelegate {
    private static let scrollMessage = "dexmaScroll"
    private static let backgroundMessage = "dexmaBackground"
    /// Reports the page's background colour (body's, else the root's) after it loads and when
    /// the system switches light/dark, so the card around the page matches it: no seam.
    private static let backgroundScript = """
        (function () {
          function post() {
            var body = document.body ? getComputedStyle(document.body).backgroundColor : '';
            var root = getComputedStyle(document.documentElement).backgroundColor;
            window.webkit.messageHandlers.\(backgroundMessage).postMessage({ body: body, root: root });
          }
          addEventListener('load', post);
          matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () { setTimeout(post, 50); });
          post();
        })();
        """
    /// Reports whether the page is scrolled to its end, so a swipe up there can close the panel
    /// (as at the terminal's newest output) instead of scrolling, and whether it can still
    /// scroll sideways either way, so a sideways swipe there scrolls it rather than the tabs.
    private static let scrollScript = """
        (function () {
          function post() {
            var page = document.scrollingElement || document.documentElement;
            var x = window.scrollX, maxX = page.scrollWidth - window.innerWidth;
            window.webkit.messageHandlers.\(scrollMessage).postMessage({
              bottom: Math.ceil(window.innerHeight + window.scrollY) >= page.scrollHeight - 2,
              left: x > 1,
              right: x < maxX - 1
            });
          }
          addEventListener('scroll', post, { passive: true });
          addEventListener('resize', post);
          addEventListener('load', post);
          post();
        })();
        """
    /// Focuses claude.ai's message box: the first visible editor in the composer. Never throws
    /// into the page; reports whether it found one.
    static let focusComposerScript = """
        (function () {
          try {
            var selectors = ['div.ProseMirror[contenteditable="true"]', 'fieldset [contenteditable="true"]',
                             '[contenteditable="true"]', 'textarea'];
            for (var i = 0; i < selectors.length; i++) {
              var all = document.querySelectorAll(selectors[i]);
              for (var j = 0; j < all.length; j++) {
                var el = all[j], box = el.getBoundingClientRect();
                if (box.width > 0 && box.height > 0 && getComputedStyle(el).visibility !== 'hidden') {
                  el.focus();
                  if (el.isContentEditable) {
                    var range = document.createRange();
                    range.selectNodeContents(el);
                    range.collapse(false);
                    var selection = getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);
                  }
                  return true;
                }
              }
            }
          } catch (e) {}
          return false;
        })();
        """

    let configuration: WebTabConfiguration
    let card: WebTabView
    var webView: WKWebView { card.webView }
    /// Back/forward, loading or the page changed: for the view model.
    var onStateChange: (() -> Void)?
    /// The card may look different now (a page loaded or finished loading).
    var onChange: (() -> Void)?
    var onSnapshotRefreshed: (() -> Void)?
    /// Page zoom (Claude's Settings option); applies to every web view this tab makes.
    var pageZoom: CGFloat = 1 {
        didSet {
            webView.pageZoom = pageZoom
            spare?.pageZoom = pageZoom
        }
    }

    /// Shared by every web view this tab makes: one set of scripts and handlers.
    private let contentController = WKUserContentController()
    /// Made ahead (idle), swapped in by `reset` (Search).
    private var spare: WKWebView?
    private let downloads = WebDownloads()
    private var popups: [WebPopupController] = []
    private var pageAtBottom = true
    private var pageCanScrollLeft = false
    private var pageCanScrollRight = false
    private var cachedSnapshot: ContentSnapshot?
    /// WebKit's latest picture of the page, and whether the page changed since.
    private var pageImage: CGImage?
    private var pageImageStale = true
    private var pageCaptureInFlight = false
    /// A Google search to fall back to if a guessed address can't be reached.
    private var fallback: URL?
    /// The user typed since the last search: page loads mustn't overwrite the field.
    private var fieldEdited = false
    private var pageHadFocus = false
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WebTabConfiguration, size: CGSize) {
        self.configuration = configuration
        let webView = Self.makeWebView(size: size, controller: contentController)
        card = WebTabView(size: size, webView: webView, hasField: configuration.hasSearchField)
        super.init()
        // The handlers are retained by the content controller; both live as long as the app.
        contentController.add(self, name: Self.scrollMessage)
        contentController.add(self, name: Self.backgroundMessage)
        installScripts()
        if configuration.hasSearchField {
            card.field.delegate = self
            card.field.target = self
            card.field.action = #selector(submit)
            spare = Self.makeWebView(size: size, controller: contentController)
        }
        adopt(webView)
        if let home = configuration.home {
            // Pre-warm: loaded now, so the tab is instant the first time it's shown.
            card.showsPage = true
            webView.load(URLRequest(url: home))
        }
    }

    /// Every page's scripts: the tab's own, then `pageScript`.
    private func installScripts() {
        contentController.removeAllUserScripts()
        contentController.addUserScript(
            WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        contentController.addUserScript(
            WKUserScript(source: Self.backgroundScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if let pageScript {
            contentController.addUserScript(
                WKUserScript(source: pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }

    /// An extra script run at the start of every page (the floating glass's page style), from the
    /// next page load on; nil: none.
    var pageScript: String? {
        didSet { if pageScript != oldValue { installScripts() } }
    }

    /// Where the page is shown: the notch (dark, on the card's colour, as always) or floating
    /// glass (the system's appearance; `clear`: no background at all, so the glass shows through).
    func setPresentation(glass: Bool, clear: Bool) {
        let appearance = glass ? nil : NSAppearance(named: .darkAqua)
        card.appearance = appearance
        webView.appearance = appearance
        card.drawsCardBackground = !(glass && clear)
        pageTakesKeyboardByItself = !glass
        Self.setDrawsBackground(!(glass && clear), of: webView)
    }

    /// Whether the page may take the keyboard by itself (`KeyboardGuardedWebView`); the floating
    /// glass keeps it for its own field.
    var pageTakesKeyboardByItself = true {
        didSet {
            let views: [WKWebView?] = [webView, spare]
            for case let view as KeyboardGuardedWebView in views {
                view.takesKeyboardByItself = pageTakesKeyboardByItself
            }
        }
    }

    /// The keyboard to the page (DEXMA's own doing: allowed even when the page may not take it).
    func focusPage() {
        if let guarded = webView as? KeyboardGuardedWebView {
            guarded.takeKeyboard()
        } else {
            card.window?.makeFirstResponder(webView)
        }
    }

    /// WKWebView on macOS has no public switch for its own background (`underPageBackgroundColor`
    /// only covers the overscroll area): `drawsBackground` is WebKit's private property, set through
    /// KVC only if WebKit still answers to it (otherwise the page keeps its background).
    private static func setDrawsBackground(_ draws: Bool, of webView: WKWebView) {
        guard webView.responds(to: NSSelectorFromString("_setDrawsBackground:"))
                || webView.responds(to: NSSelectorFromString("setDrawsBackground:")) else { return }
        webView.setValue(draws, forKey: "drawsBackground")
        webView.underPageBackgroundColor = draws ? nil : .clear
    }

    /// A web view of this tab: dark, Safari's user agent, the tab's scripts, the shared
    /// persistent website data (cookies survive restarts).
    private static func makeWebView(size: CGSize, controller: WKUserContentController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        // Without it, WebKit's user agent lacks the Safari token and sites serve a bare page.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = KeyboardGuardedWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false  // Sideways swipes switch tabs.
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.alphaValue = 0  // Until its first page has loaded: no white flash.
        return webView
    }

    /// Makes `webView` the live one: delegates and the state the band watches.
    private func adopt(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = pageZoom
        let changed: (WKWebView, Any) -> Void = { [weak self] _, _ in self?.onStateChange?() }
        observations = [
            webView.observe(\.canGoBack) { view, change in changed(view, change) },
            webView.observe(\.canGoForward) { view, change in changed(view, change) },
            webView.observe(\.isLoading) { view, change in changed(view, change) },
            webView.observe(\.url) { view, change in changed(view, change) },
        ]
    }

    // MARK: State

    /// The page's host without "www.", for the band (Claude's site name before anything loads).
    var domain: String {
        guard card.showsPage, let host = webView.url?.host else { return card.showsPage ? configuration.fallbackDomain : "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The page came over HTTPS (or the tab's site, before its page is there).
    var isSecure: Bool {
        guard card.showsPage else { return false }
        guard let scheme = webView.url?.scheme else { return !configuration.fallbackDomain.isEmpty }
        return scheme == "https"
    }

    var url: URL? { webView.url }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    var isLoading: Bool { webView.isLoading }
    /// A page is showing (not Search's empty state).
    var hasPage: Bool { card.showsPage }

    /// Whether the page shows its end (or there is no page): a swipe up may close the panel.
    var isScrolledToBottom: Bool {
        !card.showsPage || pageAtBottom
    }

    /// Whether the page itself can scroll further sideways toward `direction` (+1: content moving
    /// left, i.e. toward its right edge; −1 the other way). No page: no.
    func canScrollHorizontally(toward direction: Int) -> Bool {
        guard card.showsPage else { return false }
        return direction > 0 ? pageCanScrollRight : pageCanScrollLeft
    }

    // MARK: Focus

    /// Search: the field, its text selected, so typing starts a new search.
    func focusField() {
        guard configuration.hasSearchField, let window = card.window else { return }
        if card.field.currentEditor() == nil { window.makeFirstResponder(card.field) }
        card.field.currentEditor()?.selectAll(nil)
    }

    /// The panel is closing: remember whether the page or the field had the keyboard, so the
    /// next open picks up there (hiding the card while closed takes the keyboard away).
    func rememberFocus(in window: NSWindow) {
        pageHadFocus = (window.firstResponder as? NSView)?.isDescendant(of: webView) ?? false
    }

    /// Search: the page you were reading, else the field. Claude: the message box.
    func restoreFocus() {
        guard card.window != nil else { return }
        switch configuration.kind {
        case .search:
            if pageHadFocus, card.showsPage { focusPage() } else { focusField() }
        case .claude:
            focusPage()
            focusComposer()
        }
    }

    /// Claude's message box gets the caret (silently does nothing if it isn't found).
    func focusComposer() {
        webView.evaluateJavaScript(Self.focusComposerScript) { _, _ in }
    }

    // MARK: Actions

    /// Text from the search field or the band's ⌘L field: an address, or words to search.
    func load(_ text: String) {
        guard let target = SearchQuery.target(for: text) else { return }
        fieldEdited = false
        fallback = target.fallback
        card.showsPage = true
        webView.load(URLRequest(url: target.url))
        focusPage()
        onChange?()
    }

    func load(_ url: URL) {
        card.showsPage = true
        webView.load(URLRequest(url: url))
        onChange?()
    }

    /// Claude: a new conversation (the history stays).
    func goHome() {
        guard let home = configuration.home else { return }
        load(home)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// The current page in the default browser. Returns whether there was one.
    @discardableResult
    func openInBrowser() -> Bool {
        guard let url = webView.url else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Search: back to the empty state with no history. The spare web view takes over at once,
    /// and a new spare is made a moment later, off the click.
    func reset() {
        guard configuration.hasSearchField else { return }
        let old = webView
        let fresh = spare ?? Self.makeWebView(size: card.bounds.size, controller: contentController)
        spare = nil
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        let hadFocus = (card.window?.firstResponder as? NSView)?.isDescendant(of: old) ?? false
        card.replaceWebView(with: fresh)
        (fresh as? KeyboardGuardedWebView)?.takesKeyboardByItself = pageTakesKeyboardByItself
        adopt(fresh)
        card.showsPage = false
        card.cardColor = WebTabView.defaultColor
        card.field.stringValue = ""
        fieldEdited = false
        fallback = nil
        pageImage = nil
        pageAtBottom = true
        pageCanScrollLeft = false
        pageCanScrollRight = false
        if hadFocus || card.window?.isKeyWindow == true { focusField() }
        onStateChange?()
        onChange?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.spare == nil else { return }
            self.spare = Self.makeWebView(size: self.card.bounds.size, controller: self.contentController)
        }
    }

    func resize(to size: CGSize) {
        guard card.frame.size != size else { return }
        card.setFrameSize(size)
        spare?.setFrameSize(size)
    }

    @objc private func submit() {
        load(card.field.stringValue)
    }

    // MARK: MotionContent

    func motionSnapshot() -> ContentSnapshot? {
        if cachedSnapshot == nil { cachedSnapshot = card.capture(page: pageImage) }
        return cachedSnapshot
    }

    func invalidateSnapshot() {
        cachedSnapshot = nil
        pageImageStale = true
    }

    /// The field and the empty state are pictured right away; the page is asked of WebKit
    /// (asynchronous, out of process) and composed in when it arrives.
    func refreshSnapshot() {
        guard card.showsPage, card.revealsPage, pageImageStale, !card.isHidden, card.window != nil else {
            _ = motionSnapshot()
            return
        }
        guard !pageCaptureInFlight else { return }
        pageCaptureInFlight = true
        pageImageStale = false
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false  // What's on screen now; no extra render.
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self else { return }
            self.pageCaptureInFlight = false
            if let image = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self.pageImage = image
            }
            self.cachedSnapshot = nil
            self.onSnapshotRefreshed?()
        }
    }

    /// Anything reaching the card may change the page (WebKit doesn't say what it drew).
    func isChanged(by type: NSEvent.EventType) -> Bool {
        true
    }

    func didReappear() -> Bool {
        false
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        fieldEdited = true
        onChange?()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url else { return .allow }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch configuration.policy.decide(url, isMainFrame: isMainFrame) {
        case .allow:
            return .allow
        case .openExternally:
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async
        -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageAtBottom = false  // A new page starts at its top; the script reports soon.
        pageCanScrollLeft = false
        pageCanScrollRight = false
        if configuration.hasSearchField, !fieldEdited, let url = webView.url,
           ["http", "https"].contains(url.scheme ?? "") {
            card.field.stringValue = SearchQuery.displayText(for: url)
        }
        onStateChange?()
        onChange?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fallback = nil
        card.revealsPage = true
        onChange?()
        // Images and results often fill in just after: picture the page again a bit later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onChange?() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let code = (error as NSError).code
        // Replaced by another navigation, or turned into a download / an outside app.
        guard code != NSURLErrorCancelled, code != 102 else { return }
        if let fallback, [NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
                          NSURLErrorCannotConnectToHost].contains(code) {
            self.fallback = nil
            webView.load(URLRequest(url: fallback))
            return
        }
        fallback = nil
        card.revealsPage = true
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        webView.loadHTMLString("""
            <html><body style="background:#1c1c1e;color:#999;font:13px -apple-system;\
            display:flex;align-items:center;justify-content:center;height:90vh;margin:0">\
            \(message)</body></html>
            """, baseURL: nil)
    }

    // MARK: WKUIDelegate

    /// A link or script opening a new window. Search: it opens in the tab. Claude: a sign-in
    /// window (Google, Apple) opens as a real popup, so it can report back to the page; other
    /// sites go to the default browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        switch self.configuration.kind {
        case .search:
            webView.load(navigationAction.request)
            return nil
        case .claude:
            let blank = url == nil || url?.absoluteString.isEmpty == true || url?.scheme == "about"
            if !blank, let url, self.configuration.policy.decide(url, isMainFrame: true) == .openExternally {
                NSWorkspace.shared.open(url)
                return nil
            }
            // WebKit requires the popup to be made with exactly the configuration it hands over
            // (that's what ties it to its opener).
            let popupView = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
            popupView.appearance = NSAppearance(named: .darkAqua)
            popupView.uiDelegate = self
            let popup = WebPopupController(webView: popupView, parent: card.window)
            popup.onClose = { [weak self, weak popup] in self?.popups.removeAll { $0 === popup } }
            popups.append(popup)
            popup.show()
            return popup.webView
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.webView === webView }?.close()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let state = message.body as? [String: Any] else { return }
        if message.name == Self.backgroundMessage {
            updateCardColor(body: state["body"] as? String, root: state["root"] as? String)
            return
        }
        guard message.name == Self.scrollMessage else { return }
        pageAtBottom = state["bottom"] as? Bool ?? pageAtBottom
        pageCanScrollLeft = state["left"] as? Bool ?? false
        pageCanScrollRight = state["right"] as? Bool ?? false
        onChange?()  // Scrolled (also by keyboard or script): the page's picture is stale.
    }

    /// The card takes the page's background (body's if it has one, else the root's, else what
    /// WebKit paints under the page), so its edges show no seam.
    private func updateCardColor(body: String?, root: String?) {
        let parsed = [body, root].compactMap { $0.flatMap(CSSColor.init) }.first { !$0.isTransparent }
        let color = parsed.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            ?? webView.underPageBackgroundColor ?? WebTabView.defaultColor
        guard color != card.cardColor else { return }
        card.cardColor = color
        onChange?()
    }

    #if DEBUG
    var debugPopupWebViews: [WKWebView] { popups.map(\.webView) }
    #endif
}
