#if DEBUG
import AppKit

/// Debug builds only: the status item's "Mock Devices" menu, a fake pair of Buds driven through
/// the same `DeviceStore` path as the real ones (so the tab, the band, the connect peek and the
/// low battery alerts all react exactly as they would). Saved like any device, but a Release
/// build drops it when it loads the store.
final class MockDevices: NSObject {
    static let id = "mock:buds"

    private let store: DeviceStore
    private var levels: [ComponentRole: Int] = [.left: 82, .right: 76, .case: 45]
    private var charging = false

    init(store: DeviceStore) {
        self.store = store
        super.init()
    }

    private var isConnected: Bool {
        store.device(Self.id)?.isConnected ?? false
    }

    func menuItem() -> NSMenuItem {
        let menu = NSMenu()
        let connected = isConnected
        menu.addItem(item(connected ? "Disconnect Buds" : "Connect Buds",
                          connected ? #selector(disconnect) : #selector(connect)))
        menu.addItem(.separator())
        menu.addItem(item("Random Levels", #selector(randomLevels), enabled: connected))
        menu.addItem(item("Take a Bud Out (Case Unknown)", #selector(caseUnknown), enabled: connected))
        let chargingItem = item("Charging", #selector(toggleCharging), enabled: connected)
        chargingItem.state = charging ? .on : .off
        menu.addItem(chargingItem)
        menu.addItem(item("Drain Left Bud (→ 20 % → 10 % → 5 %)", #selector(drainLeft), enabled: connected))
        menu.addItem(.separator())
        menu.addItem(item("Forget Mock Buds", #selector(forget), enabled: store.device(Self.id) != nil))
        let root = NSMenuItem(title: "Mock Devices", action: nil, keyEquivalent: "")
        root.submenu = menu
        return root
    }

    // MARK: Actions

    /// Connects, then sends the first reading a moment later, like real Buds.
    @objc private func connect() {
        store.deviceConnected(id: Self.id, name: "Mock Buds", kind: .buds, source: .mock, model: "Galaxy Buds3 Pro")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.send() }
    }

    @objc private func disconnect() {
        store.deviceDisconnected(id: Self.id)
    }

    @objc private func randomLevels() {
        levels[.left] = Int.random(in: 25...100)
        levels[.right] = Int.random(in: 25...100)
        levels[.case] = Int.random(in: 10...100)
        send()
    }

    /// No bud in the case: the case is unknown and must keep its previous value and time.
    @objc private func caseUnknown() {
        levels[.left] = max((levels[.left] ?? 50) - 1, 1)
        send(caseKnown: false)
    }

    @objc private func toggleCharging() {
        charging.toggle()
        send()
    }

    @objc private func drainLeft() {
        let left = levels[.left] ?? 50
        levels[.left] = left > 20 ? 20 : left > 10 ? 10 : 5
        send()
    }

    @objc private func forget() {
        store.forget(Self.id)
    }

    // MARK: Private

    private func send(caseKnown: Bool = true) {
        guard isConnected else { return }
        store.apply(BatteryReading(components: [
            ComponentReading(role: .left, level: levels[.left], isCharging: charging),
            ComponentReading(role: .right, level: levels[.right], isCharging: charging),
            ComponentReading(role: .case, level: caseKnown ? levels[.case] : nil, isCharging: false),
        ]), to: Self.id)
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
        item.target = self
        return item
    }
}
#endif
