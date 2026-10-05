/// What Return does in the floating glass field.
nonisolated enum GlassInputMode: Equatable {
    /// Ask Claude: the text (and a capture) goes into claude.ai's message box and is sent.
    case ask
    /// ⌘L: a link to open in the card (e.g. an email sign-in link).
    case link

    var placeholder: String {
        switch self {
        case .ask: "Ask Claude…"
        case .link: "Paste a link to open…"
        }
    }

    var symbol: String {
        switch self {
        case .ask: "sparkle"
        case .link: "link"
        }
    }
}
