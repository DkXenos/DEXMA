import AppKit
import WebKit

/// Owns the Search tab's one long-lived card (search field + web view). Created at launch like
/// the shell, but loads nothing until the first search; never recreated, so the page, its
/// history and its scroll position survive closing the panel. A spare web view waits ready, so
/// Reset (back to the empty state, history gone) is instant.
final class SearchSession: NSObject, MotionContent, WKNavigationDelegate, WKUIDelegate,
                           WKScriptMessageHandler, NSTextFieldDelegate {
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

    let card: SearchCardView
    var webView: WKWebView { card.webView }
    /// Shared by every web view this tab makes: one set of scripts and handlers.
    private let contentController = WKUserContentController()
    /// Made ahead (idle), swapped in by `reset`.
    private var spare: WKWebView?
    /// Back/forward, loading or the page changed: for the view model.
    var onStateChange: (() -> Void)?
    /// The card may look different now (a page loaded or finished loading).
    var onChange: (() -> Void)?
    var onSnapshotRefreshed: (() -> Void)?
    /// Whether the page shows its end (or there is no page): a swipe up may close the panel.
    var isScrolledToBottom: Bool {
        !card.showsPage || pageAtBottom
    }

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

    init(size: CGSize) {
        let webView = Self.makeWebView(size: size, controller: contentController)
        card = SearchCardView(size: size, webView: webView)
        super.init()
        // The handlers are retained by the content controller; both live as long as the app.
        contentController.add(self, name: Self.scrollMessage)
        contentController.add(self, name: Self.backgroundMessage)
        contentController.addUserScript(
            WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        contentController.addUserScript(
            WKUserScript(source: Self.backgroundScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        card.field.delegate = self
        card.field.target = self
        card.field.action = #selector(submit)
        adopt(webView)
        spare = Self.makeWebView(size: size, controller: contentController)
    }

    /// A web view of this tab: dark, Safari's user agent, the tab's scripts, the shared
    /// persistent website data (cookies survive restarts).
    private static func makeWebView(size: CGSize, controller: WKUserContentController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        // Without it, WebKit's user agent lacks the Safari token and Google serves a bare page.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false  // Sideways swipes switch tabs.
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.alphaValue = 0  // Until its first page has loaded: no white flash.
        return webView
    }

    /// Makes `webView` the live one: delegates and the state the band watches.
    private func adopt(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let changed: (WKWebView, Any) -> Void = { [weak self] _, _ in self?.onStateChange?() }
        observations = [
            webView.observe(\.canGoBack) { view, change in changed(view, change) },
            webView.observe(\.canGoForward) { view, change in changed(view, change) },
            webView.observe(\.isLoading) { view, change in changed(view, change) },
            webView.observe(\.url) { view, change in changed(view, change) },
        ]
    }

    // MARK: Actions

    /// Makes the field first responder with its text selected, so typing starts a new search.
    func focusField() {
        guard let window = card.window else { return }
        if card.field.currentEditor() == nil { window.makeFirstResponder(card.field) }
        card.field.currentEditor()?.selectAll(nil)
    }

    /// The panel is closing: remember whether the page or the field had the keyboard, so the
    /// next open picks up there (hiding the card while closed takes the keyboard away).
    func rememberFocus(in window: NSWindow) {
        pageHadFocus = (window.firstResponder as? NSView)?.isDescendant(of: webView) ?? false
    }

    /// Gives the keyboard back where it was: the page you were reading, else the field.
    func restoreFocus() {
        if pageHadFocus, card.showsPage, let window = card.window {
            window.makeFirstResponder(webView)
        } else {
            focusField()
        }
    }

    func load(_ text: String) {
        guard let target = SearchQuery.target(for: text) else { return }
        fieldEdited = false
        fallback = target.fallback
        card.showsPage = true
        webView.load(URLRequest(url: target.url))
        card.window?.makeFirstResponder(webView)
        onChange?()
    }

    /// Whether the page itself can scroll further sideways toward `direction` (+1: content moving
    /// left, i.e. toward its right edge; −1 the other way). No page: no.
    func canScrollHorizontally(toward direction: Int) -> Bool {
        guard card.showsPage else { return false }
        return direction > 0 ? pageCanScrollRight : pageCanScrollLeft
    }

    /// The page's host without "www.", for the band; empty with no page.
    var domain: String {
        guard card.showsPage, let host = webView.url?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The page came over HTTPS.
    var isSecure: Bool {
        card.showsPage && webView.url?.scheme == "https"
    }

    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    var isLoading: Bool { webView.isLoading }
    /// A search has been made: the page replaced the empty state.
    var hasPage: Bool { card.showsPage }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func openInBrowser() {
        guard let url = webView.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Back to the empty state with no history: the spare web view takes over at once, and a
    /// new spare is made a moment later, off the click.
    func reset() {
        let old = webView
        let fresh = spare ?? Self.makeWebView(size: card.bounds.size, controller: contentController)
        spare = nil
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        let hadFocus = (card.window?.firstResponder as? NSView)?.isDescendant(of: old) ?? false
        card.replaceWebView(with: fresh)
        adopt(fresh)
        card.showsPage = false
        card.cardColor = SearchCardView.defaultColor
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
        guard card.showsPage, pageImageStale, !card.isHidden, card.window != nil else {
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
        // mailto:, facetime:, App Store links… belong to other apps.
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
              !["http", "https", "about", "data", "blob", "file"].contains(scheme) else { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageAtBottom = false  // A new page starts at its top; the script reports soon.
        pageCanScrollLeft = false
        pageCanScrollRight = false
        if !fieldEdited, let url = webView.url, ["http", "https"].contains(url.scheme ?? "") {
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
        guard code != NSURLErrorCancelled else { return }  // Replaced by another navigation.
        if let fallback, [NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
                          NSURLErrorCannotConnectToHost].contains(code) {
            self.fallback = nil
            webView.load(URLRequest(url: fallback))
            return
        }
        fallback = nil
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        webView.loadHTMLString("""
            <html><body style="background:#000;color:#999;font:13px -apple-system;\
            display:flex;align-items:center;justify-content:center;height:90vh;margin:0">\
            \(message)</body></html>
            """, baseURL: nil)
    }

    // MARK: WKUIDelegate

    /// Links that open a new window (target=_blank) open here instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
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
            ?? webView.underPageBackgroundColor ?? SearchCardView.defaultColor
        guard color != card.cardColor else { return }
        card.cardColor = color
        onChange?()
    }
}
