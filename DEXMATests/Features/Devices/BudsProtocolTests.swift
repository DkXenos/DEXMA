import Testing
@testable import DEXMA

struct BudsProtocolTests {
    // MARK: Checksum and framing

    @Test func checksumIsCRC16XModem() {
        #expect(BudsChecksum.crc16(Array("123456789".utf8)) == 0x31C3)  // The standard check value.
        // The sample frame in GalaxyBudsClient's notes: id 0x61 + payload, CRC sent as 0F F3.
        let body: [UInt8] = [0x61, 0x02, 0x00, 0x4B, 0x5F, 0x01, 0x00, 0x00, 0x00, 0x01, 0x05, 0x00, 0x02, 0x00, 0x13]
        #expect(BudsChecksum.crc16(body) == 0xF30F)
    }

    @Test func decodesAFrameSplitAcrossChunks() {
        let message = BudsMessage(id: 0x60, payload: [1, 80, 75, 1, 0, 0x11, 40, 0])
        let bytes = BudsFrameDecoder.encode(message, framing: .standard)
        #expect(bytes.first == 0xFD && bytes.last == 0xDD)
        #expect(bytes[1] == UInt8(1 + 8 + 2) && bytes[2] == 0)  // Size: id + payload + CRC.
        var decoder = BudsFrameDecoder(framing: .standard)
        #expect(decoder.feed(Array(bytes[..<5])).isEmpty)
        #expect(decoder.feed(Array(bytes[5...])) == [message])
    }

    @Test func dropsJunkAndCorruptFramesButKeepsTheNextOne() {
        let good = BudsMessage(id: 0x60, payload: [1, 50, 60, 1, 0, 0x11, 70, 0])
        var corrupt = BudsFrameDecoder.encode(BudsMessage(id: 0x60, payload: [1, 99, 99, 1, 0, 0x11, 99, 0]),
                                              framing: .standard)
        corrupt[6] ^= 0xFF  // Breaks the checksum.
        var badEnd = BudsFrameDecoder.encode(good, framing: .standard)
        badEnd[badEnd.count - 1] = 0x00
        var decoder = BudsFrameDecoder(framing: .standard)
        let stream = [0x00, 0x13, 0xDD] + corrupt + badEnd + BudsFrameDecoder.encode(good, framing: .standard)
        #expect(decoder.feed(stream) == [good])
        #expect(decoder.rejected >= 2)
    }

    @Test func skipsFragmentsAndReadsTheLegacyFraming() {
        var fragment = BudsFrameDecoder.encode(BudsMessage(id: 0x60, payload: [1, 2]), framing: .standard)
        fragment[2] |= 0x20  // Header bit 0x2000.
        let next = BudsMessage(id: 0x61, payload: [1, 2, 3])
        var decoder = BudsFrameDecoder(framing: .standard)
        #expect(decoder.feed(fragment + BudsFrameDecoder.encode(next, framing: .standard)) == [next])

        let legacy = BudsMessage(id: 0x60, payload: [0, 90, 85, 1, 0, 3])
        let bytes = BudsFrameDecoder.encode(legacy, framing: .legacy)
        #expect(bytes.first == 0xFE && bytes.last == 0xEE)
        var legacyDecoder = BudsFrameDecoder(framing: .legacy)
        #expect(legacyDecoder.feed(bytes) == [legacy])
    }

    // MARK: Status messages

    /// A Buds3 Pro extended status: L 80 (worn), R 75 (in the case, charging), case 40.
    private func buds3ProExtendedStatus(caseLevel: UInt8 = 40, charging: UInt8 = 0x04) -> BudsMessage {
        var payload = [UInt8](repeating: 0, count: 50)
        payload[0] = 1      // revision
        payload[2] = 80     // left
        payload[3] = 75     // right
        payload[4] = 1      // coupled
        payload[6] = 0x13   // left wearing, right in the case
        payload[7] = caseLevel
        payload[42] = charging
        return BudsMessage(id: BudsMessage.extendedStatusUpdated, payload: payload)
    }

    @Test func readsTheBuds3ProExtendedStatusWithChargingBits() throws {
        let reading = try #require(BudsStatusParser.reading(from: buds3ProExtendedStatus(), model: .buds3Pro))
        #expect(reading.components == [
            ComponentReading(role: .left, level: 80, isCharging: false),
            ComponentReading(role: .right, level: 75, isCharging: true),
            ComponentReading(role: .case, level: 40, isCharging: false),
        ])
    }

    @Test func caseWithoutABudInItAndDisconnectedBudsAreUnknown() throws {
        let reading = try #require(BudsStatusParser.reading(from: buds3ProExtendedStatus(caseLevel: 101), model: .buds3Pro))
        #expect(reading.level(.case) == nil)
        var payload: [UInt8] = [1, 64, 0, 1, 0, 0x20, 101, 0]  // Right bud not connected (nibble 0).
        let status = try #require(BudsStatusParser.reading(from: BudsMessage(id: 0x60, payload: payload), model: .buds3Pro))
        #expect(status.level(.left) == 64 && status.level(.right) == nil && status.level(.case) == nil)
        payload[7] = 0xFF  // Bits that mean nothing: charging unknown, levels still read.
        let odd = try #require(BudsStatusParser.reading(from: BudsMessage(id: 0x60, payload: payload), model: .buds3Pro))
        #expect(odd.components.allSatisfy { $0.isCharging == nil } && odd.level(.left) == 64)
    }

    @Test func statusLayoutsPerModel() throws {
        let message = BudsMessage(id: 0x60, payload: [1, 55, 66, 1, 0, 0x11, 77, 0x10])
        let modern = try #require(BudsStatusParser.reading(from: message, model: .buds3Pro))
        #expect(modern.components.map(\.isCharging) == [true, false, false])
        // Buds+: no charging bits; original Buds: no case.
        let plus = try #require(BudsStatusParser.reading(from: message, model: .budsPlus))
        #expect(plus.components.allSatisfy { $0.isCharging == nil } && plus.level(.case) == 77)
        let legacy = try #require(BudsStatusParser.reading(from: message, model: .buds))
        #expect(legacy.components.map(\.role) == [.left, .right])
        // Not a status message, or too short for one: nothing.
        #expect(BudsStatusParser.reading(from: BudsMessage(id: 0x88, payload: [1, 2, 3]), model: .buds3Pro) == nil)
        #expect(BudsStatusParser.reading(from: BudsMessage(id: 0x61, payload: [1, 0, 50]), model: .buds3Pro) == nil)
    }

    // MARK: Identification

    @Test func renamedBudsAreFoundByTheirServices() {
        let samsung = BudsModel.samsungServiceUUID
        #expect(BudsIdentification.model(name: "Mewo", serviceUUIDs: [samsung]) == .unknownSamsung)
        // The model id service, exactly as Mewo (Buds3 Pro, 340 = 0x154) lists it.
        let modelID = "d908aab5-7a90-4cbe-8641-86a553db0154"
        #expect(BudsIdentification.model(name: "Mewo", serviceUUIDs: [samsung, modelID]) == .buds3Pro)
        #expect(BudsIdentification.model(name: "Mewo", serviceUUIDs: [modelID.uppercased()]) == .buds3Pro)
        #expect(BudsIdentification.model(name: "Mewo", serviceUUIDs: ["0000110b-0000-1000-8000-00805f9b34fb"]) == nil)
    }

    @Test func defaultNamesNameTheModel() {
        #expect(BudsIdentification.model(name: "Galaxy Buds3 Pro (A1B2)", serviceUUIDs: []) == .buds3Pro)
        #expect(BudsIdentification.model(name: "Galaxy Buds3 (A1B2)", serviceUUIDs: []) == .buds3)
        #expect(BudsIdentification.model(name: "Galaxy Buds2 Pro", serviceUUIDs: []) == .buds2Pro)
        #expect(BudsIdentification.model(name: "Galaxy Buds Pro (77E1)", serviceUUIDs: []) == .budsPro)
        #expect(BudsIdentification.model(name: "Galaxy Buds (1A2B)", serviceUUIDs: []) == .buds)
        #expect(BudsIdentification.model(name: "Jason's AirPods Pro", serviceUUIDs: []) == nil)
        // Named Buds+ but its records lack their service: not readable.
        #expect(BudsIdentification.model(name: "Galaxy Buds+ (11AA)", serviceUUIDs: ["0000110b-0000-1000-8000-00805f9b34fb"]) == nil)
    }

    @Test func headsetsAreCandidatesForAQuery() {
        #expect(BudsIdentification.isCandidate(name: "Mewo", classOfDevice: 0x240404))  // Audio, headset.
        #expect(!BudsIdentification.isCandidate(name: "Pebble K380s", classOfDevice: 0x002540))  // Keyboard.
        #expect(BudsIdentification.isCandidate(name: "Galaxy Buds2 Pro", classOfDevice: 0))
    }
}
