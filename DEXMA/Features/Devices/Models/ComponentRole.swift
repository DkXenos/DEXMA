/// One battery of a device: a bud, the case, or the device itself.
nonisolated enum ComponentRole: String, Codable, CaseIterable, Comparable {
    case left
    case right
    case `case`
    case main

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .case: "Case"
        case .main: "Battery"
        }
    }

    /// In the band's summary and the connect peek ("L 80%"); empty for the device itself.
    var shortTitle: String {
        switch self {
        case .left: "L"
        case .right: "R"
        case .case: "Case"
        case .main: ""
        }
    }

    /// A bud (or the device itself) that can run low while worn; the case never alerts.
    var alertsWhenLow: Bool {
        self != .case
    }

    static func < (a: ComponentRole, b: ComponentRole) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}
