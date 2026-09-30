import AppKit
import ApplicationServices
import Observation

/// Accessibility trust, observed live (TCC has no change notification, so it's polled while
/// someone is looking — e.g. the onboarding window is open).
@Observable
final class AccessibilityPermission {
    private(set) var isGranted = AXIsProcessTrusted()
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
        let granted = AXIsProcessTrusted()
        if granted != isGranted { isGranted = granted }
    }

    /// Adds DEXMA to the Accessibility list (with the system prompt) and opens the pane.
    func requestAccess() {
        // The option key is a CF global; its string value avoids a non-Sendable global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
