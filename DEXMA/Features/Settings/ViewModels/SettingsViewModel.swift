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
    private let gestures: GestureEngine
    private let hotKey: HotKeyRegistrar
    @ObservationIgnored private weak var router: (any WindowRouter)?

    init(settings: AppSettings, accessibility: AccessibilityPermission,
         screenRecording: ScreenRecordingPermission, gestures: GestureEngine,
         hotKey: HotKeyRegistrar, router: any WindowRouter) {
        self.settings = settings
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.gestures = gestures
        self.hotKey = hotKey
        self.router = router
        launchesAtLogin = LoginItem.isEnabled
    }

    /// False when another app holds the shortcut.
    var isHotKeyWorking: Bool { hotKey.isWorking }
    /// False without a multitouch trackpad (the gesture engine stays off).
    var areGesturesAvailable: Bool { gestures.isRunning }
    var isAccessibilityGranted: Bool { accessibility.isGranted }
    var isScreenRecordingGranted: Bool { screenRecording.isGranted }
    var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func setLaunchesAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchesAtLogin = LoginItem.isEnabled  // May need approval in System Settings first.
    }

    /// The shortcut recorder started or stopped listening.
    func setRecordingShortcut(_ recording: Bool) {
        hotKey.isPaused = recording
    }

    func requestAccessibility() { accessibility.requestAccess() }
    func requestScreenRecording() { screenRecording.requestAccess() }
    func showWelcome() { router?.showWelcome() }

    // MARK: Window

    /// Permissions are polled, and touches reach the preview, only while the window is open.
    func windowDidOpen() {
        accessibility.startMonitoring()
        screenRecording.startMonitoring()
        gestures.onTouches = { [weak self] touches in self?.trackpadPreview.touches = touches }
        launchesAtLogin = LoginItem.isEnabled  // The menu bar item may have changed it.
    }

    func windowWillClose() {
        accessibility.stopMonitoring()
        screenRecording.stopMonitoring()
        hotKey.isPaused = false
        gestures.onTouches = nil
        trackpadPreview.touches = []
    }
}
