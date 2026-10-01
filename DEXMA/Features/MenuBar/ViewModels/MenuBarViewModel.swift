import AppKit

/// What the menu bar item's menu shows and does. The actions are Objective-C methods, so menu
/// items (including the app menu's Settings… item) target the view model directly.
final class MenuBarViewModel: NSObject {
    private let settings: AppSettings
    private let notch: NotchViewModel
    private weak var router: (any WindowRouter)?

    init(settings: AppSettings, notch: NotchViewModel, router: any WindowRouter) {
        self.settings = settings
        self.notch = notch
        self.router = router
    }

    var toggleTitle: String {
        notch.isOpen ? "Close Terminal" : "Open Terminal"
    }

    /// The global shortcut, shown next to the toggle item.
    var shortcut: KeyCombo {
        settings.hotKey
    }

    var launchesAtLogin: Bool {
        LoginItem.isEnabled
    }

    @objc func togglePanel() { notch.toggle() }
    @objc func openSettings() { router?.showSettings() }
    @objc func openWelcome() { router?.showWelcome() }
    @objc func toggleLaunchAtLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc func quit() { NSApp.terminate(nil) }
}
