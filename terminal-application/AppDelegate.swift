import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        let panel = NotchPanel(frame: geometry.panelFrame)
        let controller = PanelController(panel: panel, geometry: geometry)

        let hostingView = NSHostingView(rootView: NotchContentView(controller: controller))
        hostingView.sizingOptions = []  // Fixed-size panel: SwiftUI must never resize it.
        panel.contentView = hostingView
        // Pre-warm: the panel stays on screen from launch. Closed, it hides under the notch.
        panel.orderFrontRegardless()

        hotKey = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey) { controller.toggle() }
        self.controller = controller
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let screen = NotchGeometry.notchedScreen() else { return }
        controller?.updateGeometry(NotchGeometry(screen: screen))
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
