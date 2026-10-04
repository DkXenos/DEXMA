/// The short forms of a device's battery: the band's summary on the Devices tab and the
/// connect peek's parts. Unknown batteries are left out. Pure.
nonisolated enum DeviceSummary {
    /// "Mewo  L 80%  R 75%  Case 40%".
    static func band(_ device: Device) -> String {
        ([device.name] + levels(device).map(\.text)).joined(separator: "  ")
    }

    /// The connect peek (`isAlert`: a low battery alert).
    static func activity(_ device: Device, isAlert: Bool) -> DeviceActivity {
        DeviceActivity(deviceID: device.id, symbol: device.kind.symbol, parts: levels(device),
                       isAlert: isAlert)
    }

    private static func levels(_ device: Device) -> [DeviceActivity.Part] {
        device.displayedComponents.compactMap { component in
            guard let level = component.level else { return nil }
            let label = component.role.shortTitle
            return DeviceActivity.Part(role: component.role, text: label.isEmpty ? "\(level)%" : "\(label) \(level)%",
                                       isLow: component.isLow, isCharging: component.isCharging == true)
        }
    }
}
