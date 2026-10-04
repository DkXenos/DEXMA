import AppKit
import Observation

/// Everything the Settings window shows and does. The settings themselves are bound directly
/// (`AppSettings` saves and applies every change); the rest is live status from the services
/// and actions on them.
@Observable
final class SettingsViewModel {
    let settings: AppSettings
    let trackpadPreview = TrackpadPreviewViewModel()
    private(set) var launchesAtLogin: Bool

    private let accessibility: AccessibilityPermission
    private let screenRecording: ScreenRecordingPermission
    private let bluetooth: BluetoothPermission
    /// The Devices tab's devices (Settings → Forget).
    private let devices: DevicesViewModel
    private let gestures: GestureEngine
    /// The panel's shortcut, then Draw to ask's.
    private let hotKeys: [HotKeyRegistrar]
    @ObservationIgnored private weak var router: (any WindowRouter)?

    init(settings: AppSettings, accessibility: AccessibilityPermission,
         screenRecording: ScreenRecordingPermission, bluetooth: BluetoothPermission, devices: DevicesViewModel,
         gestures: GestureEngine, hotKeys: [HotKeyRegistrar], router: any WindowRouter) {
        self.settings = settings
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.bluetooth = bluetooth
        self.devices = devices
        self.gestures = gestures
        self.hotKeys = hotKeys
        self.router = router
        launchesAtLogin = LoginItem.isEnabled
    }

    /// False when another app holds the shortcut.
    var isHotKeyWorking: Bool { hotKeys.first?.isWorking ?? true }
    var isCaptureHotKeyWorking: Bool { hotKeys.last?.isWorking ?? true }
    /// Both shortcuts are the same combination (only one of them would work).
    var hotKeysClash: Bool { settings.hotKey == settings.captureHotKey }
    /// False without a multitouch trackpad (the gesture engine stays off).
    var areGesturesAvailable: Bool { gestures.isRunning }
    var isAccessibilityGranted: Bool { accessibility.isGranted }
    var isScreenRecordingGranted: Bool { screenRecording.isGranted }
    var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isBluetoothGranted: Bool { bluetooth.isGranted }
    var isBluetoothDenied: Bool { bluetooth.isDenied }
    /// Every remembered device, connected first.
    var knownDevices: [Device] { devices.devices }

    func deviceStatus(_ device: Device) -> String { devices.status(device) }
    func forget(_ device: Device) { devices.forget(device) }
    func openBluetoothSettings() { bluetooth.openSettings() }

    func setLaunchesAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchesAtLogin = LoginItem.isEnabled  // May need approval in System Settings first.
    }

    /// A shortcut recorder started or stopped listening: neither global shortcut may fire
    /// meanwhile (either could be typed as the new one).
    func setRecordingShortcut(_ recording: Bool) {
        for hotKey in hotKeys { hotKey.isPaused = recording }
    }

    func requestAccessibility() { accessibility.requestAccess() }
    func requestScreenRecording() { screenRecording.requestAccess() }
    func showWelcome() { router?.showWelcome() }

    // MARK: Window

    /// Permissions are polled, and touches reach the preview, only while the window is open.
    func windowDidOpen() {
        accessibility.startMonitoring()
        screenRecording.startMonitoring()
        bluetooth.startMonitoring()
        gestures.onTouches = { [weak self] touches in self?.trackpadPreview.touches = touches }
        launchesAtLogin = LoginItem.isEnabled  // The menu bar item may have changed it.
    }

    func windowWillClose() {
        accessibility.stopMonitoring()
        screenRecording.stopMonitoring()
        bluetooth.stopMonitoring()
        for hotKey in hotKeys { hotKey.isPaused = false }
        gestures.onTouches = nil
        trackpadPreview.touches = []
    }
}
