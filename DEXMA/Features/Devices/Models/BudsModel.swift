/// The Galaxy Buds models DEXMA can read, with everything that differs between them: the
/// RFCOMM service to open, the framing, and where the batteries are in the two status messages.
/// Byte offsets and ids are protocol facts learned from GalaxyBudsClient (see CLAUDE.md,
/// *Devices*); the Buds3 Pro ("Mewo") is the model tested first.
nonisolated enum BudsModel: String, CaseIterable, Codable {
    case buds
    case budsPlus
    case budsLive
    case budsPro
    case buds2
    case buds2Pro
    case budsFE
    case budsCore
    case buds3
    case buds3Pro
    case buds3FE
    case buds4
    case buds4Pro
    /// Has Samsung's newer status service but nothing more specific is known (e.g. renamed and
    /// no model id in its service records): read like a Buds2.
    case unknownSamsung

    /// The status service: original Buds, Buds+/Live/Pro (the standard Serial Port profile),
    /// and Samsung's own service on the Buds2 and later.
    static let legacyServiceUUID = "00001102-0000-1000-8000-00805f9b34fd"
    static let serialPortServiceUUID = "00001101-0000-1000-8000-00805f9b34fb"
    static let samsungServiceUUID = "2e73a4ad-332d-41fc-90e2-16bef06523f2"
    /// Buds2 and later also list a service UUID made of this prefix and their model id
    /// (`deviceIDs`) in hex, which identifies them even when renamed.
    static let modelIDServicePrefix = "d908aab5-7a90-4cbe-8641-86a553db"

    var displayName: String {
        switch self {
        case .buds: "Galaxy Buds"
        case .budsPlus: "Galaxy Buds+"
        case .budsLive: "Galaxy Buds Live"
        case .budsPro: "Galaxy Buds Pro"
        case .buds2: "Galaxy Buds2"
        case .buds2Pro: "Galaxy Buds2 Pro"
        case .budsFE: "Galaxy Buds FE"
        case .budsCore: "Galaxy Buds Core"
        case .buds3: "Galaxy Buds3"
        case .buds3Pro: "Galaxy Buds3 Pro"
        case .buds3FE: "Galaxy Buds3 FE"
        case .buds4: "Galaxy Buds4"
        case .buds4Pro: "Galaxy Buds4 Pro"
        case .unknownSamsung: "Galaxy Buds"
        }
    }

    /// Part of the default Bluetooth name ("Galaxy Buds3 Pro (A1B2)").
    var nameHint: String? {
        switch self {
        case .buds, .unknownSamsung: nil  // "Galaxy Buds" alone: see `BudsIdentification`.
        case .budsPlus: "Buds+"
        case .budsLive: "Buds Live"
        case .budsPro: "Buds Pro"
        case .buds2: "Buds2"
        case .buds2Pro: "Buds2 Pro"
        case .budsFE: "Buds FE"
        case .budsCore: "Buds Core"
        case .buds3: "Buds3"
        case .buds3Pro: "Buds3 Pro"
        case .buds3FE: "Buds3 FE"
        case .buds4: "Buds4"
        case .buds4Pro: "Buds4 Pro"
        }
    }

    /// Samsung's model ids (one per colour), as in the model id service UUID.
    var deviceIDs: [UInt32] {
        switch self {
        case .buds: [257, 14336]
        case .budsPlus: Array(258...266)
        case .budsLive: Array(278...284)
        case .budsPro: Array(298...301)
        case .buds2: Array(313...321) + [14337]
        case .budsCore: [322, 323]
        case .buds2Pro: Array(325...328)
        case .budsFE: [330, 331]
        case .buds3: [333, 334]
        case .buds3Pro: [340, 341]
        case .buds3FE: [347, 348]
        case .buds4: [355, 356]
        case .buds4Pro: [359, 360]
        case .unknownSamsung: []
        }
    }

    var serviceUUID: String {
        switch self {
        case .buds: Self.legacyServiceUUID
        case .budsPlus, .budsLive, .budsPro: Self.serialPortServiceUUID
        default: Self.samsungServiceUUID
        }
    }

    var framing: BudsFraming {
        self == .buds ? .legacy : .standard
    }

    /// STATUS_UPDATED (0x60): [revision, L, R, coupled, main bud, placement, case, charging].
    /// The original Buds have no case; charging bits start with the Buds2.
    var statusLayout: BudsStatusLayout {
        switch self {
        case .buds:
            BudsStatusLayout(left: 1, right: 2)
        case .budsPlus, .budsLive, .budsPro:
            BudsStatusLayout(left: 1, right: 2, placement: 5, caseLevel: 6)
        default:
            BudsStatusLayout(left: 1, right: 2, placement: 5, caseLevel: 6, charging: 7)
        }
    }

    /// EXTENDED_STATUS_UPDATED (0x61): [revision, ear type, L, R, coupled, main bud, placement,
    /// case, …settings…]; the charging bits sit after the model's settings (unknown where the
    /// offset depends on the firmware revision: the next STATUS_UPDATED brings them).
    var extendedStatusLayout: BudsStatusLayout {
        switch self {
        case .buds:
            BudsStatusLayout(left: 2, right: 3)
        case .budsPlus, .budsLive, .budsPro, .buds2, .buds2Pro, .unknownSamsung:
            BudsStatusLayout(left: 2, right: 3, placement: 6, caseLevel: 7)
        case .budsFE, .budsCore, .buds3FE:
            BudsStatusLayout(left: 2, right: 3, placement: 6, caseLevel: 7, charging: 43)
        case .buds3, .buds3Pro, .buds4, .buds4Pro:
            BudsStatusLayout(left: 2, right: 3, placement: 6, caseLevel: 7, charging: 42)
        }
    }

    var hasCase: Bool {
        self != .buds
    }
}
