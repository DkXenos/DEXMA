import Foundation

/// One battery of a device and when it was last read. Each keeps its own time: the case is
/// usually older than the buds (it only reports while a bud is in it).
nonisolated struct DeviceComponent: Codable, Equatable {
    static let lowLevel = 20

    var role: ComponentRole
    /// 0…100; nil until it has been read once.
    var level: Int?
    /// Nil when the source doesn't say.
    var isCharging: Bool?
    var updatedAt: Date?

    var isKnown: Bool { level != nil }

    /// At or below 20 % and not charging: drawn red.
    var isLow: Bool {
        guard let level else { return false }
        return level <= Self.lowLevel && isCharging != true
    }
}
