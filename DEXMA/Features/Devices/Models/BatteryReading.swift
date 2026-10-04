/// What a source read from a device at one moment: some or all of its batteries.
nonisolated struct BatteryReading: Equatable {
    var components: [ComponentReading]

    /// At least one battery has a value (a reading of only unknowns changes nothing).
    var hasLevel: Bool {
        components.contains { $0.level != nil }
    }

    func level(_ role: ComponentRole) -> Int? {
        components.first { $0.role == role }?.level
    }
}
