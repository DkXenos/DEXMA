/// The panel's tabs, in the band left of the notch (⌘1, ⌘2).
enum PanelTab: CaseIterable {
    case terminal
    case search

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "apple.terminal"
        case .search: "magnifyingglass"
        }
    }
}
