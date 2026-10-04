/// Reads the batteries out of a status message for a model (`BudsModel`'s layouts). A level
/// outside 1…100 (0 from a bud that isn't connected, 101 from the case while no bud is in it)
/// or a bud reported as not connected counts as unknown, so the device keeps its previous value
/// for it; a charging byte with bits that mean nothing is ignored. Any other message, or one too
/// short for its layout, gives nil. Pure.
nonisolated enum BudsStatusParser {
    static func reading(from message: BudsMessage, model: BudsModel) -> BatteryReading? {
        let layout: BudsStatusLayout
        switch message.id {
        case BudsMessage.statusUpdated: layout = model.statusLayout
        case BudsMessage.extendedStatusUpdated: layout = model.extendedStatusLayout
        default: return nil
        }
        let payload = message.payload
        guard payload.count > max(layout.left, layout.right) else { return nil }
        func byte(_ offset: Int?) -> UInt8? {
            guard let offset, offset < payload.count else { return nil }
            return payload[offset]
        }
        func level(_ value: UInt8?) -> Int? {
            guard let value, (1...100).contains(value) else { return nil }
            return Int(value)
        }
        // 0 = this bud isn't connected (its level is stale or zero).
        let placement = byte(layout.placement)
        let leftConnected = placement.map { $0 >> 4 != 0 } ?? true
        let rightConnected = placement.map { $0 & 0x0F != 0 } ?? true
        // Only 0x10 (left), 0x04 (right) and 0x01 (case) mean anything.
        let charging = byte(layout.charging).flatMap { $0 & ~0x15 == 0 ? $0 : nil }
        func isCharging(_ bit: UInt8) -> Bool? {
            charging.map { $0 & bit != 0 }
        }

        var parts = [
            ComponentReading(role: .left, level: leftConnected ? level(payload[layout.left]) : nil,
                             isCharging: isCharging(0x10)),
            ComponentReading(role: .right, level: rightConnected ? level(payload[layout.right]) : nil,
                             isCharging: isCharging(0x04)),
        ]
        if model.hasCase {
            parts.append(ComponentReading(role: .case, level: level(byte(layout.caseLevel)),
                                          isCharging: isCharging(0x01)))
        }
        return BatteryReading(components: parts)
    }
}
