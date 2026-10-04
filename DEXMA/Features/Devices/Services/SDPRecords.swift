import Foundation
import IOBluetooth

/// Reading a Bluetooth device's SDP service records (the ones macOS has cached, or that a
/// query just brought in): the services' UUIDs, and the RFCOMM channel of one service.
enum SDPRecords {
    /// The ServiceClassIDList attribute: the UUIDs a service record says it implements.
    private static let serviceClassIDList: BluetoothSDPServiceAttributeID = 0x0001

    /// Every service class UUID in the device's records, lowercase 128-bit strings. macOS's
    /// cached records keep a one-UUID list as the bare UUID element, not a sequence (the Buds3
    /// Pro's are all like that), so both forms are read.
    static func serviceUUIDs(of device: IOBluetoothDevice) -> [String] {
        let records = (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }
        return records.flatMap { record in
            record.getAttributeDataElement(serviceClassIDList).map(uuids) ?? []
        }
    }

    /// The UUIDs in a data element: itself if it's a UUID, its items if it's a sequence or
    /// an alternative.
    private nonisolated static func uuids(in element: IOBluetoothSDPDataElement) -> [String] {
        switch element.getTypeDescriptor() {
        case BluetoothSDPDataElementTypeDescriptor(kBluetoothSDPDataElementTypeUUID):
            return element.getUUIDValue().flatMap(string).map { [$0] } ?? []
        case BluetoothSDPDataElementTypeDescriptor(kBluetoothSDPDataElementTypeDataElementSequence),
             BluetoothSDPDataElementTypeDescriptor(kBluetoothSDPDataElementTypeDataElementAlternative):
            return (element.getArrayValue() ?? []).compactMap { $0 as? IOBluetoothSDPDataElement }.flatMap(uuids)
        default:
            return []
        }
    }

    /// The RFCOMM channel of the service with `uuid`, if the device has it.
    static func rfcommChannel(of device: IOBluetoothDevice, service uuid: String) -> BluetoothRFCOMMChannelID? {
        guard let sdpUUID = sdpUUID(uuid), let record = device.getServiceRecord(for: sdpUUID) else { return nil }
        var channel: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&channel) == kIOReturnSuccess ? channel : nil
    }

    /// "2e73a4ad-332d-…" → the SDP UUID (16 bytes, big-endian).
    static func sdpUUID(_ string: String) -> IOBluetoothSDPUUID? {
        let hex = Array(string.filter(\.isHexDigit))
        guard hex.count == 32 else { return nil }
        let bytes = stride(from: 0, to: 32, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
        guard bytes.count == 16 else { return nil }
        return IOBluetoothSDPUUID(bytes: bytes, length: 16)
    }

    /// Any SDP UUID (16, 32 or 128 bits) as a lowercase 128-bit string.
    private nonisolated static func string(_ uuid: IOBluetoothSDPUUID) -> String? {
        guard let full = uuid.getWithLength(16), full.length == 16 else { return nil }
        let hex = (full as Data).map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}
