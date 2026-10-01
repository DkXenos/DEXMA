import AppKit
import Observation

/// The sheet shown when Draw to ask is used without Screen Recording: why it's needed, a button
/// to the right System Settings pane, and live status. Once granted it checks that capture
/// really works; if macOS wants DEXMA reopened first, it offers that.
@Observable
final class CaptureOnboardingViewModel {
    enum Status: Equatable {
        case needsPermission
        /// Granted: checking that ScreenCaptureKit agrees.
        case checking
        /// Granted, but capture only works after DEXMA reopens.
        case needsRelaunch
        case ready
    }

    private(set) var status: Status = .needsPermission
    /// The capture shortcut as shown, e.g. "⌥⇧`".
    let shortcut: String
    /// Closes the window; set by its window controller.
    @ObservationIgnored var dismiss: (() -> Void)?
    /// "Draw now": the window closes and capture starts.
    @ObservationIgnored var onDrawNow: (() -> Void)?

    @ObservationIgnored private let permission: ScreenRecordingPermission
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var verifying = false

    init(permission: ScreenRecordingPermission, shortcut: String) {
        self.permission = permission
        self.shortcut = shortcut
    }

    func openSystemSettings() {
        permission.requestAccess()
    }

    func drawNow() {
        dismiss?()
        // After the window has gone, so it isn't in the frozen picture's way.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.onDrawNow?() }
    }

    /// Opens a fresh copy of DEXMA a moment after this one quits (macOS sometimes only lets
    /// capture start working in a new process).
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    // MARK: Window

    /// Polled once a second while the window is open (TCC has no change notification).
    func windowDidOpen() {
        permission.startMonitoring()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }  // Scheduled on the main run loop.
        }
    }

    func windowWillClose() {
        timer?.invalidate()
        timer = nil
        permission.stopMonitoring()
    }

    private func update() {
        guard permission.isGranted else {
            status = .needsPermission
            return
        }
        guard status == .needsPermission || status == .checking, !verifying else { return }
        status = .checking
        verifying = true
        Task {
            let works = await ScreenFreezer.isWorking()
            verifying = false
            status = works ? .ready : .needsRelaunch
        }
    }
}
