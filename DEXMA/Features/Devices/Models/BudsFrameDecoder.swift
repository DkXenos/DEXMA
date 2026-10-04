/// Cuts the RFCOMM byte stream into messages (`BudsFraming`). Bytes arrive in arbitrary
/// chunks: an incomplete message waits for the rest. Anything malformed (wrong start or end
/// byte, impossible size, bad checksum) is dropped one byte at a time until the next start
/// byte, so one corrupt message never takes the following ones with it. Fragments (only used
/// for firmware and log transfers) are skipped. Pure.
nonisolated struct BudsFrameDecoder {
    /// Never buffer more than this: a stream of junk can't grow without bound.
    static let maxBuffered = 4096

    let framing: BudsFraming
    private var buffer: [UInt8] = []
    /// Malformed frames dropped so far (for the log).
    private(set) var rejected = 0

    init(framing: BudsFraming) {
        self.framing = framing
    }

    mutating func feed(_ bytes: [UInt8]) -> [BudsMessage] {
        buffer.append(contentsOf: bytes)
        var messages: [BudsMessage] = []
        while true {
            // Skip to the next start byte.
            guard let start = buffer.firstIndex(of: framing.startOfMessage) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 4 else { break }
            let size: Int
            var isFragment = false
            switch framing {
            case .legacy:
                size = Int(buffer[2])
            case .standard:
                let header = UInt16(buffer[1]) | UInt16(buffer[2]) << 8
                size = Int(header & 0x3FF)
                isFragment = header & 0x2000 != 0
            }
            // id + CRC at least.
            guard size >= 3 else {
                drop()
                continue
            }
            let total = 3 + size + 1
            guard buffer.count >= total else {
                if buffer.count > Self.maxBuffered { drop() } else { break }
                continue
            }
            let body = buffer[3..<(3 + size - 2)]  // id + payload
            let crc = UInt16(buffer[3 + size - 2]) | UInt16(buffer[3 + size - 1]) << 8
            guard buffer[total - 1] == framing.endOfMessage, BudsChecksum.crc16(body) == crc else {
                drop()
                continue
            }
            if !isFragment, let id = body.first {
                messages.append(BudsMessage(id: id, payload: Array(body.dropFirst())))
            }
            buffer.removeFirst(total)
        }
        return messages
    }

    /// The frame at the front is malformed: resynchronise from the next start byte.
    private mutating func drop() {
        rejected += 1
        buffer.removeFirst()
    }

    /// Frames a message the way the Buds do (for tests and the Debug mock).
    static func encode(_ message: BudsMessage, framing: BudsFraming) -> [UInt8] {
        let size = 1 + message.payload.count + 2
        let header: [UInt8] = switch framing {
        case .legacy: [0x00, UInt8(size & 0xFF)]
        case .standard: [UInt8(size & 0xFF), UInt8((size >> 8) & 0x03)]
        }
        let body = [message.id] + message.payload
        let crc = BudsChecksum.crc16(body)
        return [framing.startOfMessage] + header + body + [UInt8(crc & 0xFF), UInt8(crc >> 8), framing.endOfMessage]
    }
}
