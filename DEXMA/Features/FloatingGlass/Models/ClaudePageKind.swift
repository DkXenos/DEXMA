import Foundation

/// What claude.ai is showing, from its address (pure): the floating glass opens its card for a
/// conversation or anything that needs the page itself (signing in), and stays a field on a new chat.
nonisolated enum ClaudePageKind: Equatable {
    /// A new chat (claude.ai/new or the home page): nothing to show yet.
    case newChat
    /// A conversation (claude.ai/chat/…, a project's chat…).
    case conversation
    /// Signing in (claude.ai's own pages, Google's or Apple's).
    case signIn
    /// Any other page of the site (settings, projects…), or nothing loaded yet.
    case other

    init(url: URL?) {
        guard let url, let host = url.host?.lowercased() else {
            self = .other
            return
        }
        guard host == "claude.ai" || host.hasSuffix(".claude.ai") else {
            self = host.contains("google") || host.contains("apple") ? .signIn : .other
            return
        }
        let path = url.path
        if path == "/" || path.isEmpty || path == "/new" {
            self = .newChat
        } else if path.hasPrefix("/chat/") {
            self = .conversation
        } else if ["/login", "/logout", "/magic-link", "/signup", "/sso", "/onboarding"].contains(where: { path.hasPrefix($0) }) {
            self = .signIn
        } else {
            self = .other
        }
    }

    /// The card opens by itself for this page.
    var showsPage: Bool { self != .newChat }
}
