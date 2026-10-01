import AppKit

/// What the menu bar item's menu shows and does. The actions are Objective-C methods, so menu
/// items (including the app menu's Settings… item) target the view model directly.
final class MenuBarViewModel: NSObject {
    private let settings: AppSettings
    private let notch: NotchViewModel
    private let capture: CaptureViewModel
    private weak var router: (any WindowRouter)?

    init(settings: AppSettings, notch: NotchViewModel, capture: CaptureViewModel, router: any WindowRouter) {
        self.settings = settings
        self.notch = notch
        self.capture = capture
        self.router = router
    }

    var toggleTitle: String {
        notch.isOpen ? "Close Terminal" : "Open Terminal"
    }

    /// The global shortcut, shown next to the toggle item.
    var shortcut: KeyCombo {
        settings.hotKey
    }

    /// Draw to ask's shortcut, shown next to its item.
    var captureShortcut: KeyCombo {
        settings.captureHotKey
    }

    var launchesAtLogin: Bool {
        LoginItem.isEnabled
    }

    @objc func togglePanel() { notch.toggle() }
    /// From the menu: once the menu has closed, so it isn't in the frozen picture.
    @objc func startCapture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [capture] in capture.start() }
    }
    @objc func openSettings() { router?.showSettings() }
    @objc func openWelcome() { router?.showWelcome() }
    @objc func toggleLaunchAtLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc func quit() { NSApp.terminate(nil) }
}
