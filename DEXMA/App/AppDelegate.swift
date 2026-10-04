import AppKit

/// App lifecycle only: launch and screen changes go to `AppCoordinator`, which builds and owns
/// everything else.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    /// SIGTERM (e.g. `scripts/dexma` replacing the running app) quits normally, so
    /// `applicationWillTerminate` still saves what's pending.
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
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
