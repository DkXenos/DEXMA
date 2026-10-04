import Foundation
import Observation

/// The Devices tab and its band summary, and when the notch peeks: on the first reading after
/// a device connects ("Show battery peek on connect") and when a bud drops to 20 % and 10 %
/// ("Low battery alerts"). Relative times ("Last seen 2h ago") update exactly when their text
/// changes — a single timer aimed at the next change, none while nothing shows a time.
@Observable
final class DevicesViewModel {
    let store: DeviceStore
    let bluetooth: BluetoothPermission
    /// "Now" for the relative times; moves on only when one of them would read differently.
    private(set) var now = Date()

    @ObservationIgnored var peeksOnConnect = true
    @ObservationIgnored var lowBatteryAlerts = true
    @ObservationIgnored var peeksInFullScreen = false
    @ObservationIgnored weak var activityTarget: DeviceActivityTarget?
    /// Settings → Forget also stops the source reading it (until it connects again).
    @ObservationIgnored var onForget: ((String) -> Void)?

    @ObservationIgnored private var policies: [String: LowBatteryPolicy] = [:]
    @ObservationIgnored private var clock: DispatchWorkItem?

    init(store: DeviceStore, bluetooth: BluetoothPermission) {
        self.store = store
        self.bluetooth = bluetooth
        store.onEvent = { [weak self] event in self?.handle(event) }
        scheduleClock()
    }

    /// Connected first, then the most recently seen.
    var devices: [Device] {
        store.devices.sorted { a, b in
            a.isConnected != b.isConnected ? a.isConnected : a.lastSeen > b.lastSeen
        }
    }

    /// The band's summary on the Devices tab: the most recent device's levels.
    var bandSummary: String {
        devices.first.map(DeviceSummary.band) ?? ""
    }

    /// Bluetooth access was refused: the empty Devices tab says where to allow it.
    var isBluetoothDenied: Bool {
        bluetooth.isDenied
    }

    /// "Connected", or "Last seen 2h ago".
    func status(_ device: Device) -> String {
        device.isConnected ? "Connected" : "Last seen \(RelativeTime.text(since: device.lastSeen, now: now))"
    }

    /// "3h ago" under a battery read well before the device's others (e.g. the case).
    func age(_ component: DeviceComponent, of device: Device) -> String? {
        guard device.isStale(component), let time = component.updatedAt else { return nil }
        return RelativeTime.text(since: time, now: now)
    }

    func forget(_ device: Device) {
        policies.removeValue(forKey: device.id)
        onForget?(device.id)
        store.forget(device.id)
        scheduleClock()
    }

    // MARK: Events

    private func handle(_ event: DeviceStore.Event) {
        switch event {
        case .connected(let device):
            policies[device.id] = LowBatteryPolicy()
        case .firstReading(let device):
            var policy = policies[device.id] ?? LowBatteryPolicy()
            _ = policy.observe(Self.reading(of: device), isFirstReading: true)
            policies[device.id] = policy
            if peeksOnConnect {
                let isLow = device.displayedComponents.contains(where: \.isLow)
                activityTarget?.showDeviceActivity(DeviceSummary.activity(device, isAlert: isLow),
                                                   allowedInFullScreen: peeksInFullScreen)
            }
        case .reading(let device):
            guard device.isConnected else { break }
            var policy = policies[device.id] ?? LowBatteryPolicy()
            let alert = policy.observe(Self.reading(of: device), isFirstReading: false)
            policies[device.id] = policy
            if alert != nil, lowBatteryAlerts {
                activityTarget?.showDeviceActivity(DeviceSummary.activity(device, isAlert: true),
                                                   allowedInFullScreen: peeksInFullScreen)
            } else {
                activityTarget?.updateDeviceActivity(DeviceSummary.activity(device, isAlert: false))
            }
        case .disconnected(let device):
            policies.removeValue(forKey: device.id)
        }
        now = Date()
        scheduleClock()
    }

    private static func reading(of device: Device) -> BatteryReading {
        BatteryReading(components: device.displayedComponents.map {
            ComponentReading(role: $0.role, level: $0.level, isCharging: $0.isCharging)
        })
    }

    // MARK: Clock

    /// Aims one timer at the next moment a shown relative time changes.
    private func scheduleClock() {
        clock?.cancel()
        clock = nil
        let current = Date()
        var times: [Date] = []
        for device in store.devices {
            if !device.isConnected { times.append(device.lastSeen) }
            times += device.displayedComponents.filter { device.isStale($0) }.compactMap(\.updatedAt)
        }
        guard let next = times.map({ RelativeTime.nextChange(since: $0, now: current) }).min() else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.now = Date()
            self.scheduleClock()
        }
        clock = work
        // A little after the boundary (wall clock: right after waking from sleep too).
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(next.timeIntervalSince(current), 0) + 0.5,
                                      execute: work)
    }
}
