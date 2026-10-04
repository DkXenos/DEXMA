import CoreBluetooth
import Foundation
import IOBluetooth
import os

/// Watches Bluetooth connections for Galaxy Buds and keeps a `BudsConnection` for each pair
/// while it's connected; reports to the `DeviceStore`. Event-driven only: IOBluetooth's connect
/// notification (any device) and a disconnect notification per pair. While no Buds are
/// connected DEXMA does no Bluetooth work at all; a connecting headset gets one SDP query at
/// most (a renamed pair looks like any headset until its services are known), and one that
/// turns out not to be Buds is left alone for the rest of the session.
final class BluetoothBudsMonitor: NSObject {
    private static let logger = Logger(category: "Buds")

    private let store: DeviceStore
    private var connectNotification: IOBluetoothUserNotification?
    private var connections: [String: BudsConnection] = [:]
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Headsets whose services showed they aren't Galaxy Buds, this session.
    private var notBuds: Set<String> = []
    private(set) var isRunning = false

    init(store: DeviceStore) {
        self.store = store
        super.init()
    }

    /// Asks for Bluetooth access the first time (macOS shows its prompt), then listens.
    func start() {
        guard !isRunning else { return }
        let authorization = CBManager.authorization
        guard authorization != .denied, authorization != .restricted else {
            Self.logger.notice("Bluetooth access denied: no Buds battery (Settings → Devices)")
            return
        }
        isRunning = true
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        // Connected before launch: the notification only reports new connections. (A local
        // list: no radio traffic.)
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            handleConnected(device)
        }
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        for id in Array(connections.keys) { drop(id) }
        isRunning = false
    }

    /// Settings → Forget: stop reading it until it connects again.
    func forget(_ id: String) {
        drop(id)
    }

    static func id(for device: IOBluetoothDevice) -> String {
        "bt:" + (device.addressString ?? "unknown").lowercased()
    }

    // MARK: Notifications (on the main run loop)

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleConnected(device)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let id = Self.id(for: device)
        let wasBuds = connections[id]?.model != nil
        drop(id)
        if wasBuds { Self.logger.notice("Buds disconnected") }
        store.deviceDisconnected(id: id)
    }

    private func handleConnected(_ device: IOBluetoothDevice) {
        let id = Self.id(for: device)
        guard connections[id] == nil, !notBuds.contains(id) else { return }
        let name = device.name ?? ""
        guard BudsIdentification.isCandidate(name: name, classOfDevice: device.classOfDevice) else { return }
        let cached = SDPRecords.serviceUUIDs(of: device)
        let model = BudsIdentification.model(name: name, serviceUUIDs: cached)
        Self.logger.notice("Headset connected: \(name, privacy: .public), \(cached.count) cached services → \(model?.displayName ?? "not identified yet", privacy: .public)")
        if model == nil, !cached.isEmpty, BudsIdentification.model(named: name) == nil {
            notBuds.insert(id)  // Its cached services already say it isn't Buds.
            Self.logger.notice("\(name, privacy: .public) isn't Galaxy Buds (cached services)")
            return
        }
        let connection = BudsConnection(device: device, id: id, model: model)
        connection.onIdentified = { [weak self, weak device] model in
            guard let self else { return }
            Self.logger.notice("\(model.displayName, privacy: .public) connected")
            let current = device?.name ?? self.store.device(id)?.name ?? model.displayName
            self.store.deviceConnected(id: id, name: current.isEmpty ? model.displayName : current, kind: .buds,
                                       source: .bluetoothBuds, model: model.displayName)
        }
        connection.onNotBuds = { [weak self] in
            self?.notBuds.insert(id)
            self?.drop(id)
        }
        connection.onReading = { [weak self] reading in
            self?.store.apply(reading, to: id)
        }
        connections[id] = connection
        disconnectNotifications[id] = device.register(forDisconnectNotification: self,
                                                      selector: #selector(deviceDisconnected(_:device:)))
        connection.start()
    }

    private func drop(_ id: String) {
        connections.removeValue(forKey: id)?.stop()
        disconnectNotifications.removeValue(forKey: id)?.unregister()
    }
}
