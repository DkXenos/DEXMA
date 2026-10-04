import Foundation
import Observation
import os

/// Every device DEXMA has seen and its batteries, whatever the source (the Buds over Bluetooth
/// now; a phone or tablet later). Sources report connects, readings and disconnects; the store
/// merges readings (`Device.apply`: unknown values keep their old ones), tells its listener
/// what happened, and saves itself to Application Support as JSON a second after the last
/// change (written off the main thread), so the values survive restarts.
@Observable
final class DeviceStore {
    enum Event {
        case connected(Device)
        /// The first reading with a level since it connected (the connect peek).
        case firstReading(Device)
        /// A later reading changed something.
        case reading(Device)
        case disconnected(Device)
    }

    private nonisolated static let logger = Logger(category: "Devices")

    private(set) var devices: [Device] = []
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var awaitingFirstReading: Set<String> = []
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "DEXMA.DeviceStore", qos: .utility)

    /// `fileURL`: where to keep the devices (nil: memory only, for tests).
    init(fileURL: URL? = DeviceStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// ~/Library/Application Support/DEXMA/devices.json
    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DEXMA", isDirectory: true)
            .appendingPathComponent("devices.json")
    }

    func device(_ id: String) -> Device? {
        devices.first { $0.id == id }
    }

    // MARK: Sources report

    /// `id` connected (added if new; its name and model refreshed).
    func deviceConnected(id: String, name: String, kind: DeviceKind, source: DeviceSource, model: String? = nil,
                         at date: Date = .now) {
        var device = self.device(id) ?? Device(id: id, name: name, kind: kind, source: source, lastSeen: date)
        device.name = name
        device.model = model ?? device.model
        device.isConnected = true
        device.lastSeen = date
        awaitingFirstReading.insert(id)
        store(device)
        onEvent?(.connected(device))
    }

    /// The model became known after connecting (from the device's service records).
    func setModel(_ model: String, for id: String) {
        guard var device = device(id), device.model != model else { return }
        device.model = model
        store(device)
    }

    func apply(_ reading: BatteryReading, to id: String, at date: Date = .now) {
        guard var device = device(id) else { return }
        let first = awaitingFirstReading.contains(id) && reading.hasLevel
        guard device.apply(reading, at: date) || first else { return }
        if first { awaitingFirstReading.remove(id) }
        store(device)
        onEvent?(first ? .firstReading(device) : .reading(device))
    }

    func deviceDisconnected(id: String, at date: Date = .now) {
        awaitingFirstReading.remove(id)
        guard var device = device(id), device.isConnected else { return }
        device.isConnected = false
        device.lastSeen = date
        store(device)
        onEvent?(.disconnected(device))
    }

    /// Settings → Forget: gone from the tab and the file.
    func forget(_ id: String) {
        awaitingFirstReading.remove(id)
        devices.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Persistence

    /// Writes right away (on quit: the debounced save may not have run yet).
    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let data = encoded() else { return }
        writeQueue.sync { Self.write(data, to: fileURL) }
    }

    private func store(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            if devices[index] != device { devices[index] = device }
        } else {
            devices.append(device)
        }
        scheduleSave()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = self.encoded() else { return }
            self.saveWork = nil
            let url = self.fileURL
            self.writeQueue.async { Self.write(data, to: url) }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(devices)
    }

    private nonisolated static func write(_ data: Data, to url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save devices: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var loaded = try decoder.decode([Device].self, from: data)
            // Nothing is connected until a source says so.
            for index in loaded.indices { loaded[index].isConnected = false }
            #if !DEBUG
            loaded.removeAll { $0.source == .mock }
            #endif
            devices = loaded
        } catch {
            Self.logger.error("Couldn't read devices: \(error.localizedDescription, privacy: .public)")
        }
    }
}
