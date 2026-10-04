import Foundation
import Testing
@testable import DEXMA

@MainActor
struct DeviceStoreTests {
    private func reading(_ left: Int?, _ caseLevel: Int?) -> BatteryReading {
        BatteryReading(components: [ComponentReading(role: .left, level: left),
                                    ComponentReading(role: .right, level: left),
                                    ComponentReading(role: .case, level: caseLevel)])
    }

    @Test func reportsTheFirstReadingAfterEachConnect() {
        let store = DeviceStore(fileURL: nil)
        var events: [String] = []
        store.onEvent = { event in
            switch event {
            case .connected: events.append("connected")
            case .firstReading: events.append("first")
            case .reading: events.append("reading")
            case .disconnected: events.append("disconnected")
            }
        }
        store.deviceConnected(id: "bt:1", name: "Mewo", kind: .buds, source: .bluetoothBuds)
        store.apply(reading(nil, nil), to: "bt:1")  // Nothing known yet: not the first reading.
        store.apply(reading(80, 40), to: "bt:1")
        store.apply(reading(79, nil), to: "bt:1")
        store.deviceDisconnected(id: "bt:1")
        store.deviceConnected(id: "bt:1", name: "Mewo", kind: .buds, source: .bluetoothBuds)
        store.apply(reading(79, nil), to: "bt:1")
        #expect(events == ["connected", "first", "reading", "disconnected", "connected", "first"])
        #expect(store.device("bt:1")?.component(.case)?.level == 40)
    }

    @Test func survivesARestartDisconnected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DEXMA-tests-\(UUID().uuidString)/devices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DeviceStore(fileURL: url)
        store.deviceConnected(id: "bt:1", name: "Mewo", kind: .buds, source: .bluetoothBuds, model: "Galaxy Buds3 Pro")
        store.apply(reading(80, 40), to: "bt:1")
        store.saveNow()
        let reloaded = DeviceStore(fileURL: url)
        let device = try #require(reloaded.device("bt:1"))
        #expect(!device.isConnected && device.model == "Galaxy Buds3 Pro")
        #expect(device.component(.left)?.level == 80 && device.component(.case)?.level == 40)
        // Saved to the second (ISO 8601): plenty for "3h ago".
        let saved = try #require(device.component(.case)?.updatedAt)
        let original = try #require(store.device("bt:1")?.component(.case)?.updatedAt)
        #expect(abs(saved.timeIntervalSince(original)) < 1)
        reloaded.forget("bt:1")
        #expect(reloaded.devices.isEmpty)
    }
}
