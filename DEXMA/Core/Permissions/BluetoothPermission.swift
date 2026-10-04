import AppKit
import CoreBluetooth
import Observation

/// Bluetooth access (TCC), for reading the Galaxy Buds' battery. macOS asks the first time
/// DEXMA uses Bluetooth (at launch, when the Buds monitor starts); this only reports the answer
/// — `CBManager.authorization` asks nothing and touches no radio — and opens the pane to change
/// it. Polled only while a window shows it.
@Observable
final class BluetoothPermission {
    private(set) var authorization = CBManager.authorization
    @ObservationIgnored private var timer: Timer?

    var isGranted: Bool { authorization == .allowedAlways }
    /// Denied or restricted: asking again does nothing, only System Settings can change it.
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }  // Scheduled on the main run loop.
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let current = CBManager.authorization
        if current != authorization { authorization = current }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}
