/// How a Galaxy Buds model frames its status messages on the RFCOMM channel:
///
///     SOM | header (2 bytes) | message id | payload | CRC-16 (2 bytes, little-endian) | EOM
///
/// The CRC covers the id and payload (`BudsChecksum`). The original Buds (2019) use FE…EE and a
/// header of [type, size]; every later model FD…DD and a little-endian 16-bit header whose low
/// 10 bits are the size (id + payload + CRC), 0x1000 the request/response flag and 0x2000 the
/// fragment flag. (Facts from GalaxyBudsClient's protocol notes and `SppMessage`; see
/// CLAUDE.md, *Devices*.)
nonisolated enum BudsFraming: Equatable {
    /// Galaxy Buds (2019).
    case legacy
    /// Buds+ and every later model.
    case standard

    var startOfMessage: UInt8 {
        switch self {
        case .legacy: 0xFE
        case .standard: 0xFD
        }
    }

    var endOfMessage: UInt8 {
        switch self {
        case .legacy: 0xEE
        case .standard: 0xDD
        }
    }
}
