import Foundation

/// Tells Galaxy Buds apart from other Bluetooth devices, and which model they are, from what
/// macOS knows locally: the name and the service UUIDs in the device's SDP records. Renamed
/// Buds (e.g. "Mewo") are found by their services: the model id service (Buds2 and later) names
/// the exact model; Samsung's status service alone says "newer Buds". Pure.
nonisolated enum BudsIdentification {
    /// `serviceUUIDs`: lowercase 128-bit UUID strings.
    static func model(name: String, serviceUUIDs: [String]) -> BudsModel? {
        let uuids = Set(serviceUUIDs.map { $0.lowercased() })
        if let model = uuids.lazy.compactMap(modelFromIDService).first {
            return model
        }
        let named = model(named: name)
        if uuids.contains(BudsModel.samsungServiceUUID) {
            // Renamed, or a model too new for the name list: its own service decides.
            if let named, named.serviceUUID == BudsModel.samsungServiceUUID { return named }
            return .unknownSamsung
        }
        guard let named else { return nil }
        // Before the services are known (no SDP query yet), the name alone is a good guess;
        // once they are, the model's service has to be there.
        return uuids.isEmpty || uuids.contains(named.serviceUUID) ? named : nil
    }

    /// Worth an SDP query on connect: a Galaxy Buds name, or any headset (a renamed pair looks
    /// like any other headset until its services are known). Bluetooth's class of device puts
    /// the major class in bits 8–12; 0x04 is audio/video.
    static func isCandidate(name: String, classOfDevice: UInt32) -> Bool {
        model(named: name) != nil || (classOfDevice >> 8) & 0x1F == 0x04
    }

    /// From the default name ("Galaxy Buds3 Pro (A1B2)"), most specific match first.
    static func model(named name: String) -> BudsModel? {
        let hinted = BudsModel.allCases
            .compactMap { model in model.nameHint.map { (model, $0) } }
            .sorted { $0.1.count > $1.1.count }
            .first { name.localizedCaseInsensitiveContains("Galaxy \($0.1)") }
        if let hinted { return hinted.0 }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed == "Galaxy Buds" || trimmed.hasPrefix("Galaxy Buds (") { return .buds }
        return nil
    }

    /// "d908aab5-7a90-4cbe-8641-86a553db" + 8 hex digits: Samsung's model id. The byte order
    /// isn't documented, so both are tried against the known ids.
    private static func modelFromIDService(_ uuid: String) -> BudsModel? {
        guard uuid.hasPrefix(BudsModel.modelIDServicePrefix) else { return nil }
        let hex = String(uuid.dropFirst(BudsModel.modelIDServicePrefix.count))
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        for id in [value, value.byteSwapped] {
            if let model = BudsModel.allCases.first(where: { $0.deviceIDs.contains(id) }) { return model }
        }
        return nil
    }
}
