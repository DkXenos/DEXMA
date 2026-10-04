/// Where a device's readings come from.
nonisolated enum DeviceSource: String, Codable {
    /// Galaxy Buds over Bluetooth (`BluetoothBudsMonitor`).
    case bluetoothBuds
    /// A future app on the phone or tablet that sends its own battery.
    case companionApp
    /// The Debug build's Mock devices menu. Dropped when a Release build loads the store.
    case mock
}
