import Foundation
import Observation

/// A web tab's state for the band (domain, lock, its buttons) and the shortcuts (back,
/// forward, reload/stop, reset, new chat, open in browser), kept in step with its `WebTab`.
@Observable
final class WebTabViewModel {
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// A page is showing (not Search's empty state): there is something to reset or open.
    private(set) var hasPage = false
    /// The page's host (no "www."), and whether it came over HTTPS: the band's context.
    private(set) var domain = ""
    private(set) var isSecure = false
    /// The page's address (Claude: /new, a conversation, the sign-in page…).
    private(set) var url: URL?

    /// The page's address changed (the floating glass expands for a conversation).
    @ObservationIgnored var onURLChange: ((URL?) -> Void)?

    /// The tab's one long-lived card and web view.
    let session: WebTab

    init(session: WebTab) {
        self.session = session
        session.onStateChange = { [weak self] in self?.update() }
        update()
    }

    var kind: WebTabConfiguration.Kind { session.configuration.kind }

    func goBack() {
        session.goBack()
    }

    func goForward() {
        session.goForward()
    }

    func reloadOrStop() {
        session.reloadOrStop()
    }

    /// Search: back to the empty state, history gone.
    func reset() {
        session.reset()
    }

    /// Claude: a new conversation in the same tab (the history stays).
    func newChat() {
        session.goHome()
    }

    /// The current page in the default browser. Returns whether there was one.
    @discardableResult
    func openInBrowser() -> Bool {
        session.openInBrowser()
    }

    private func update() {
        if canGoBack != session.canGoBack { canGoBack = session.canGoBack }
        if canGoForward != session.canGoForward { canGoForward = session.canGoForward }
        if isLoading != session.isLoading { isLoading = session.isLoading }
        if hasPage != session.hasPage { hasPage = session.hasPage }
        if domain != session.domain { domain = session.domain }
        if isSecure != session.isSecure { isSecure = session.isSecure }
        if url != session.url {
            url = session.url
            onURLChange?(url)
        }
    }
}
