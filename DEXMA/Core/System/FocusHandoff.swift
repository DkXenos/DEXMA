import AppKit

/// Gives the keyboard back to the app the user was in when the panel closes. The panel takes
/// typing without activating DEXMA, so that app stays frontmost the whole time.
final class FocusHandoff {
    private var previousApp: NSRunningApplication?

    /// The panel is about to take the keyboard: remember who had it.
    func rememberFrontmostApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost != NSRunningApplication.current { previousApp = frontmost }
    }

    /// The panel is closing; if it still has the keyboard, hand it back.
    func returnFocus(from panel: NSWindow) {
        guard panel.isKeyWindow else { return }
        // A key non-activating panel still counts as "active" to AppKit; deactivating hands
        // the keyboard back to the frontmost app right away, not after the close animation.
        NSApp.deactivate()
        previousApp?.activate()
        previousApp = nil
    }

    /// The user clicked into another app: focus already went where they clicked.
    func forget() {
        previousApp = nil
    }
}
