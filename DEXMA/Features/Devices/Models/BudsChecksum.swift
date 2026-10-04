/// CRC-16/XMODEM (CCITT polynomial 0x1021, initial value 0, no reflection), the checksum of
/// every Buds message over its id and payload. Pure.
nonisolated enum BudsChecksum {
    static func crc16<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}
