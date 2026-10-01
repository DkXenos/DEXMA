import Observation

/// The Search tab's state for the band's buttons (back, forward, reload/stop, open in the
/// browser), kept in step with the session's web view.
@Observable
final class SearchViewModel {
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// A page is loaded (not the empty state): there is something to reload or open.
    private(set) var hasPage = false

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

    private func update() {
        if canGoBack != session.canGoBack { canGoBack = session.canGoBack }
        if canGoForward != session.canGoForward { canGoForward = session.canGoForward }
        if isLoading != session.isLoading { isLoading = session.isLoading }
        if hasPage != session.hasPage { hasPage = session.hasPage }
    }
}
