#if DEBUG
import AppKit
import IOBluetooth

/// Debug-only: `DEXMA -budsprobe` runs the Buds identification on every paired headset's
/// cached SDP records (local only: no radio, no connection) and prints the model and the status
/// service's RFCOMM channel it would open, then quits.
enum BudsProbe {
    static func run() {
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            let name = device.name ?? "?"
            guard BudsIdentification.isCandidate(name: name, classOfDevice: device.classOfDevice) else { continue }
            let uuids = SDPRecords.serviceUUIDs(of: device)
            let model = BudsIdentification.model(name: name, serviceUUIDs: uuids)
            let channel = model.flatMap { SDPRecords.rfcommChannel(of: device, service: $0.serviceUUID) }
            print("[budsprobe] \(name): connected \(device.isConnected()), \(uuids.count) cached service UUIDs → \(model?.displayName ?? "not Galaxy Buds / unknown"), status channel \(channel.map(String.init) ?? "-")")
            for uuid in uuids { print("[budsprobe]     \(uuid)") }
        }
        NSApp.terminate(nil)
    }
}
#endif
