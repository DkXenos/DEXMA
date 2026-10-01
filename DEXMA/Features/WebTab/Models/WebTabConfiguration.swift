import Foundation

/// What makes a web tab Search or Claude: one `WebTab` component, two configurations.
nonisolated struct WebTabConfiguration: Equatable {
    enum Kind: Equatable {
        case search
        case claude
    }

    let kind: Kind
    /// Loaded at launch (so the tab is instant) and by New chat; nil: nothing until the first
    /// search.
    let home: URL?
    /// A search field across the top of the card (Search).
    let hasSearchField: Bool
    let policy: WebNavigationPolicy
    /// What the band calls the site when no page has loaded yet (Claude: "claude.ai").
    let fallbackDomain: String

    static let search = WebTabConfiguration(
        kind: .search, home: nil, hasSearchField: true, policy: .anyPage, fallbackDomain: "")

    /// claude.ai in the tab, and the pages its sign-in needs (Google, Apple); anything else
    /// (citations, links in answers) opens in the default browser.
    static let claude = WebTabConfiguration(
        kind: .claude, home: URL(string: "https://claude.ai/new"), hasSearchField: false,
        policy: WebNavigationPolicy(stayHosts: ["claude.ai", "anthropic.com", "accounts.google.com",
                                                "accounts.youtube.com", "appleid.apple.com"]),
        fallbackDomain: "claude.ai")
}
