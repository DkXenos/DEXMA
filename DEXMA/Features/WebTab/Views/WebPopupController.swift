import AppKit
import WebKit

/// A web page's own popup window (a sign-in with Google or Apple), opened with the web view
/// WebKit asked for so it can report back to the page that opened it. A small titled window
/// above the panel; closes when the page closes it (`webViewDidClose`) or the user does.
final class WebPopupController: NSObject, NSWindowDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?
    private let window: NSPanel

    init(webView: WKWebView, parent: NSWindow?) {
        self.webView = webView
        window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 640),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Sign In"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Above the notch panel (status bar + 1), below menus.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.delegate = self
        if let parent {
            let frame = parent.frame
            window.setFrameTopLeftPoint(CGPoint(x: frame.midX - 240, y: frame.maxY - 60))
        } else {
            window.center()
        }
    }

    func show() {
        // A popup needs the keyboard (passwords): DEXMA becomes active while it's up.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        onClose?()
    }
}
