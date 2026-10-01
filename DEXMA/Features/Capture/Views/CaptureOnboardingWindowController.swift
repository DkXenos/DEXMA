import AppKit
import SwiftUI

/// The Screen Recording sheet's window: black, no visible title bar. Tells its view model when it
/// opens and closes.
final class CaptureOnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: CaptureOnboardingViewModel

    init(viewModel: CaptureOnboardingViewModel) {
        self.viewModel = viewModel
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Draw to Ask Claude"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: CaptureOnboardingView(viewModel: viewModel))
        window.delegate = self
        viewModel.dismiss = { [weak self] in self?.window?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        viewModel.windowDidOpen()
        NSApp.activate()  // An agent app must activate for its window to come to the front.
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.windowWillClose()
    }
}
