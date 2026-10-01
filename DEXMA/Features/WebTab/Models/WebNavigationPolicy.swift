import Foundation

/// Where a link may open: inside the tab, or handed to another app (the default browser for
/// web pages, Mail for mailto:…). Pure, so it's unit-tested.
nonisolated struct WebNavigationPolicy: Equatable {
    enum Decision: Equatable {
        case allow
        case openExternally
    }

    /// Hosts whose pages stay in the tab (each also covers its subdomains); nil: every web page.
    let stayHosts: [String]?

    /// Every web page stays (Search).
    static let anyPage = WebNavigationPolicy(stayHosts: nil)

    /// `url` loading in the tab's main frame (subframes, e.g. a sign-in widget or a captcha,
    /// always stay).
    func decide(_ url: URL, isMainFrame: Bool) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .allow }
        // about:blank, data:, blob: (in-page downloads, previews) belong to the page.
        if ["about", "data", "blob", "javascript"].contains(scheme) { return .allow }
        guard scheme == "http" || scheme == "https" else { return .openExternally }  // mailto:, tel:…
        guard isMainFrame, let stayHosts else { return .allow }
        guard let host = url.host?.lowercased() else { return .openExternally }
        return stayHosts.contains { host == $0 || host.hasSuffix("." + $0) } ? .allow : .openExternally
    }
}
