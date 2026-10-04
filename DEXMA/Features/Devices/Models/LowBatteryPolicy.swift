/// When a connected device's bud (or the device itself) runs low: once as it drops to 20 %,
/// again at 10 %. Levels already that low when it connects are covered by the connect peek and
/// don't alert again; charging never alerts; climbing back above a threshold (+5) re-arms it.
/// One per connection. Pure.
nonisolated struct LowBatteryPolicy: Equatable {
    static let thresholds = [20, 10]
    static let rearmMargin = 5

    /// Per battery, the thresholds already passed this connection.
    private var passed: [ComponentRole: Set<Int>] = [:]

    /// A new reading for the device. Returns the threshold to alert for (the lowest newly
    /// crossed), or nil. `isFirstReading`: the first one since it connected.
    mutating func observe(_ reading: BatteryReading, isFirstReading: Bool) -> Int? {
        var alert: Int?
        for part in reading.components where part.role.alertsWhenLow {
            guard let level = part.level else { continue }
            var done = passed[part.role] ?? []
            done = done.filter { level <= $0 + Self.rearmMargin }
            let crossed = Self.thresholds.filter { level <= $0 && !done.contains($0) }
            if !crossed.isEmpty {
                done.formUnion(crossed)
                if !isFirstReading, part.isCharging != true, let lowest = crossed.min() {
                    alert = min(alert ?? lowest, lowest)
                }
            }
            passed[part.role] = done
        }
        return alert
    }
}
