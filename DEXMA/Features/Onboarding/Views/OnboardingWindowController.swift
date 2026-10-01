import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let permission: AccessibilityPermission
    private let screenRecording: ScreenRecordingPermission
    private let onFinish: () -> Void

    init(permission: AccessibilityPermission, screenRecording: ScreenRecordingPermission,
         shortcut: String, onFinish: @escaping () -> Void) {
        self.permission = permission
        self.screenRecording = screenRecording
        self.onFinish = onFinish
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to DEXMA"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(
            permission: permission, screenRecording: screenRecording, shortcut: shortcut,
            onDone: { [weak self] in
                self?.onFinish()
                self?.window?.close()
            }))
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        permission.startMonitoring()
        screenRecording.startMonitoring()
        NSApp.activate()  // An agent app must activate for its window to come to the front.
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // Only the user dismissing it counts as "seen" — not the app quitting with it open.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onFinish()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        permission.stopMonitoring()
        screenRecording.stopMonitoring()
    }
}
