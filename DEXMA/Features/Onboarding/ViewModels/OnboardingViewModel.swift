import Observation

/// What the welcome window shows (how to open DEXMA, live permission status) and does.
@Observable
final class OnboardingViewModel {
    /// Closes the window; set by its window controller.
    @ObservationIgnored var dismiss: (() -> Void)?

    private let settings: AppSettings
    private let accessibility: AccessibilityPermission
    private let screenRecording: ScreenRecordingPermission

    init(settings: AppSettings, accessibility: AccessibilityPermission,
         screenRecording: ScreenRecordingPermission) {
        self.settings = settings
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    /// The global shortcut as it's shown, e.g. "⌥`".
    var shortcut: String { settings.hotKey.display }
    var isAccessibilityGranted: Bool { accessibility.isGranted }
    var isScreenRecordingGranted: Bool { screenRecording.isGranted }

    func requestAccessibility() { accessibility.requestAccess() }
    func requestScreenRecording() { screenRecording.requestAccess() }

    func done() {
        markSeen()
        dismiss?()
    }

    /// Only the user dismissing the window counts as seen, not the app quitting with it open.
    func markSeen() {
        OnboardingRecord.isSeen = true
    }

    // MARK: Window

    /// Permissions are polled only while the window is open.
    func windowDidOpen() {
        accessibility.startMonitoring()
        screenRecording.startMonitoring()
    }

    func windowWillClose() {
        accessibility.stopMonitoring()
        screenRecording.stopMonitoring()
    }
}
