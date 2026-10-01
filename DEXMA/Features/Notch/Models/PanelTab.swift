/// The panel's tabs, in the switcher left of the notch (⌘1, ⌘2, ⌘3; ⌃Tab cycles).
enum PanelTab: CaseIterable {
    case terminal
    case search
    case claude

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .search: "Search"
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .search: "magnifyingglass"
        case .claude: "sparkle"
        }
    }
}
