/// What the notch shows when it grows into the connect peek (Dynamic Island style): the
/// device's icon left of the notch, its levels right of it — the buds on one line, the case
/// smaller below (so the pill stays compact). Red when it's a low battery alert.
nonisolated struct DeviceActivity: Equatable {
    struct Part: Equatable {
        var role: ComponentRole
        /// "L 80%", "Case 40%", or "80%" for a single value.
        var text: String
        var isLow: Bool
        var isCharging: Bool
    }

    var deviceID: String
    var symbol: String
    var parts: [Part]
    /// A low battery alert: the icon goes red.
    var isAlert: Bool

    /// The first line: the buds ("L 80% · R 75%"), or the single value.
    var mainParts: [Part] {
        parts.filter { $0.role != .case }
    }

    /// The second line: the case, if known.
    var casePart: Part? {
        parts.first { $0.role == .case }
    }

    /// Every part as one line ("L 80% · R 75% · Case 40%").
    var text: String {
        parts.map(\.text).joined(separator: Self.separator)
    }

    var mainText: String {
        mainParts.map(\.text).joined(separator: Self.separator)
    }

    static let separator = " · "
}
