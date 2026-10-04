import AppKit

/// App lifecycle only: launch and screen changes go to `AppCoordinator`, which builds and owns
/// everything else.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        coordinator.screenParametersDidChange()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.willTerminate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
