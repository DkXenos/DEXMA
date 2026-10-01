import AppKit
import CoreGraphics
import Observation

/// Screen Recording access, for bending the real screen around the notch. Asking only ever
/// happens from a button. Like Accessibility, TCC has no change notification, so it's polled
/// while a window that shows it is open. After granting, macOS may ask to reopen DEXMA.
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted = CGPreflightScreenCaptureAccess()
    @ObservationIgnored private var timer: Timer?

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
        let granted = CGPreflightScreenCaptureAccess()
        if granted != isGranted { isGranted = granted }
    }

    /// Shows the system prompt (first time) and opens the Screen Recording pane.
    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
