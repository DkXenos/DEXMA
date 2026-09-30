import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var session: ShellSession?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        // Pre-warm: zsh starts now and outlives every open/close.
        let session = ShellSession(size: geometry.terminalFrame.size)
        let panel = NotchPanel(frame: geometry.panelFrame)
        let controller = PanelController(panel: panel, geometry: geometry)

        let hostingView = NSHostingView(
            rootView: NotchContentView(controller: controller, session: session))
        hostingView.sizingOptions = []  // Fixed-size panel: SwiftUI must never resize it.
        panel.contentView = hostingView
        // Pre-warm: the panel stays on screen from launch. Closed, it hides under the notch.
        panel.orderFrontRegardless()

        hotKey = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey) { controller.toggle() }
        self.controller = controller
        self.session = session
        #if DEBUG
        DebugSnapshot.runIfRequested(panel: panel, controller: controller, session: session)
        #endif
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        controller?.updateGeometry(NotchGeometry(screen: screen))
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
