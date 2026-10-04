/// One battery in a reading. A nil level means the source didn't know it this time (e.g. the
/// case while no bud is in it): the device keeps what it had, with its old time.
nonisolated struct ComponentReading: Equatable {
    var role: ComponentRole
    var level: Int?
    var isCharging: Bool?
}
