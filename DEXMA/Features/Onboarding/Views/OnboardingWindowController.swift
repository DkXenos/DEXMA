import AppKit
import SwiftUI

/// The welcome window. Tells its view model when it opens and closes.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to DEXMA"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(viewModel: viewModel))
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

    // The close button counts as seen too (Done closes the window directly, without this).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        viewModel.markSeen()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.windowWillClose()
    }
}
