import Observation

/// The Search tab's state for the band (domain, lock, Reset, Open in browser) and the
/// shortcuts (back, forward, reload/stop), kept in step with the session's web view.
@Observable
final class SearchViewModel {
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// A page is loaded (not the empty state): there is something to reload or open.
    private(set) var hasPage = false
    /// The page's host (no "www."), and whether it came over HTTPS: the band's context.
    private(set) var domain = ""
    private(set) var isSecure = false

    /// The one Search card, shown in the panel.
    let session: SearchSession

    init(session: SearchSession) {
        self.session = session
        session.onStateChange = { [weak self] in self?.update() }
    }

    func goBack() {
        session.goBack()
    }

    func goForward() {
        session.goForward()
    }

    func reloadOrStop() {
        session.reloadOrStop()
    }

    func openInBrowser() {
        session.openInBrowser()
    }

    /// Back to the empty state, history gone.
    func reset() {
        session.reset()
    }

    private func update() {
        if canGoBack != session.canGoBack { canGoBack = session.canGoBack }
        if canGoForward != session.canGoForward { canGoForward = session.canGoForward }
        if isLoading != session.isLoading { isLoading = session.isLoading }
        if hasPage != session.hasPage { hasPage = session.hasPage }
        if domain != session.domain { domain = session.domain }
        if isSecure != session.isSecure { isSecure = session.isSecure }
    }
}
