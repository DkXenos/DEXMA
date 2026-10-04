/// One complete, checksum-verified message from the Buds.
nonisolated struct BudsMessage: Equatable {
    /// Sent unasked whenever a battery, placement or charging state changes.
    static let statusUpdated: UInt8 = 0x60
    /// Sent unasked right after the RFCOMM channel opens (and on some state changes): the full
    /// state, batteries included.
    static let extendedStatusUpdated: UInt8 = 0x61

    var id: UInt8
    var payload: [UInt8]
}
