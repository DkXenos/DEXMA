/// What a device is: its icon, and the parts it reports a battery for. Buds are read over
/// Bluetooth now; phones, tablets and watches are for a later source (e.g. a companion app).
nonisolated enum DeviceKind: String, Codable, CaseIterable {
    case buds
    case phone
    case tablet
    case watch
    case other

    var symbol: String {
        switch self {
        case .buds: "earbuds"
        case .phone: "smartphone"
        case .tablet: "ipad"
        case .watch: "applewatch"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    /// The parts a fresh device of this kind shows (as "—" until they're read).
    var componentRoles: [ComponentRole] {
        switch self {
        case .buds: [.left, .right, .case]
        case .phone, .tablet, .watch, .other: [.main]
        }
    }
}
