/// The panel's tabs, in the switcher left of the notch (⌘1…⌘4; ⌃Tab cycles).
enum PanelTab: CaseIterable {
    case terminal
    case search
    case claude
    case devices

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .search: "Search"
        case .claude: "Claude"
        case .devices: "Devices"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .search: "magnifyingglass"
        case .claude: "sparkle"
        case .devices: "earbuds"
        }
    }
}
