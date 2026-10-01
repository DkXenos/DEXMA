import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let permission: AccessibilityPermission
    private let screenRecording: ScreenRecordingPermission
    private let onVisibilityChange: (Bool) -> Void

    init(rootView: SettingsView, permission: AccessibilityPermission,
         screenRecording: ScreenRecordingPermission,
         onVisibilityChange: @escaping (Bool) -> Void) {
        self.permission = permission
        self.screenRecording = screenRecording
        self.onVisibilityChange = onVisibilityChange
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "DEXMA Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        permission.startMonitoring()
        screenRecording.startMonitoring()
        onVisibilityChange(true)
        NSApp.activate()  // An agent app must activate for its window to come to the front.
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        permission.stopMonitoring()
        screenRecording.stopMonitoring()
        onVisibilityChange(false)
    }
}
