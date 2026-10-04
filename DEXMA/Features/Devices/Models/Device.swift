import Foundation

/// A device whose battery DEXMA shows: live while it's connected, remembered (with when it was
/// last seen) after. Generic over where readings come from (`source`), so phones and tablets can
/// join the Buds later.
nonisolated struct Device: Codable, Equatable, Identifiable {
    /// Stable per device and source, e.g. "bt:a0-56-2c-6d-3f-40".
    var id: String
    var name: String
    var kind: DeviceKind
    var source: DeviceSource
    /// What it was identified as (e.g. "Galaxy Buds3 Pro"), if known.
    var model: String?
    /// In `ComponentRole` order.
    var components: [DeviceComponent]
    var isConnected: Bool
    /// The last time it was connected (or sent anything).
    var lastSeen: Date

    init(id: String, name: String, kind: DeviceKind, source: DeviceSource, model: String? = nil,
         components: [DeviceComponent]? = nil, isConnected: Bool = false, lastSeen: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.model = model
        self.components = components ?? kind.componentRoles.map { DeviceComponent(role: $0) }
        self.isConnected = isConnected
        self.lastSeen = lastSeen
    }

    func component(_ role: ComponentRole) -> DeviceComponent? {
        components.first { $0.role == role }
    }

    /// Takes in `reading` at `date`: every battery it knows gets its level, charging state and
    /// `date`; one it doesn't know (nil level) keeps its previous value and time. Returns whether
    /// anything changed.
    @discardableResult
    mutating func apply(_ reading: BatteryReading, at date: Date) -> Bool {
        let before = self
        for part in reading.components {
            guard let level = part.level else { continue }
            let value = DeviceComponent(role: part.role, level: min(max(level, 0), 100),
                                        isCharging: part.isCharging, updatedAt: date)
            if let index = components.firstIndex(where: { $0.role == part.role }) {
                components[index] = value
            } else {
                components.append(value)
                components.sort { $0.role < $1.role }
            }
        }
        if reading.hasLevel { lastSeen = max(lastSeen, date) }
        return self != before
    }

    /// The batteries the card shows. Normally every part but `.main`; when the newest thing
    /// known is a single value (macOS's own level, the fallback when the Buds' status channel
    /// can't be opened), just that one.
    var displayedComponents: [DeviceComponent] {
        let parts = components.filter { $0.role != .main }
        if let main = component(.main), main.isKnown, let mainTime = main.updatedAt,
           parts.allSatisfy({ ($0.updatedAt ?? .distantPast) < mainTime }) {
            return [main]
        }
        return parts.isEmpty ? components : parts
    }

    /// The newest reading time among the shown batteries.
    var latestUpdate: Date? {
        displayedComponents.compactMap(\.updatedAt).max()
    }

    /// A shown battery read a while before the rest (e.g. the case, last seen when a bud was in
    /// it): it gets its own "3h ago".
    func isStale(_ component: DeviceComponent) -> Bool {
        guard let time = component.updatedAt, let latest = latestUpdate else { return false }
        return latest.timeIntervalSince(time) >= 60
    }
}
