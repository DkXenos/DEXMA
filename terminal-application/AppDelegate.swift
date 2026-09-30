import AppKit
import Carbon.HIToolbox
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchTerm",
                                       category: "App")
    private var controller: PanelController?
    private var session: ShellSession?
    private var hotKey: HotKey?
    private var gestures: GestureEngine?
    private let scrollBlocker = ScrollBlocker()
    private let accessibility = AccessibilityPermission()
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        // Pre-warm: zsh starts now and outlives every open/close.
        let session = ShellSession(size: geometry.terminalFrame.size)
        let panel = NotchPanel(frame: geometry.panelFrame)
        let controller = PanelController(panel: panel, session: session, geometry: geometry)

        let hostingView = NSHostingView(
            rootView: NotchContentView(controller: controller, session: session))
        hostingView.sizingOptions = []  // Fixed-size panel: SwiftUI must never resize it.
        // The panel overlaps the notch and menu bar on purpose; don't let AppKit safe-area
        // insets feed back into SwiftUI layout.
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        // Pre-warm: the panel stays on screen from launch. Closed, it hides under the notch.
        panel.orderFrontRegardless()

        hotKey = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey) { controller.toggle() }
        self.controller = controller
        self.session = session

        let gestures = GestureEngine(controller: controller, session: session)
        gestures.scrollGate = scrollBlocker.gate
        let gesturesStarted = gestures.start()  // No trackpad: stays off; the hotkey still works.
        self.gestures = gestures
        // Without Accessibility this waits (polling) and starts by itself once it's granted.
        scrollBlocker.startWhenPermitted()
        Self.logger.notice(
            "Launched. Multitouch gestures: \(gesturesStarted ? "on" : "unavailable", privacy: .public); scroll blocking: \(self.scrollBlocker.isActive ? "on" : "waiting for Accessibility", privacy: .public)")

        if !UserDefaults.standard.bool(forKey: "didShowOnboarding") {
            showOnboarding()
        }
        #if DEBUG
        DebugSnapshot.runIfRequested(panel: panel, controller: controller, session: session)
        #endif
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: accessibility, shortcut: "⌥`") {
                UserDefaults.standard.set(true, forKey: "didShowOnboarding")
            }
        }
        onboarding?.show()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        controller?.updateGeometry(NotchGeometry(screen: screen))
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
