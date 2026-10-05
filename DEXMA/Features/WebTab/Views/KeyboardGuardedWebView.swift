import AppKit
import WebKit

/// A web tab's web view that can be kept from taking the keyboard by itself. A page focusing one of
/// its own fields (claude.ai focuses its message box whenever its window becomes key) makes WebKit
/// the window's first responder; in the floating glass that took the keyboard away from the native
/// field ~120 ms after it appeared, and the question went into claude.ai's hidden box instead.
/// With `takesKeyboardByItself` off, it only becomes first responder through a click into it or
/// `takeKeyboard()`.
final class KeyboardGuardedWebView: WKWebView {
    /// The page may take the keyboard by itself (the notch: yes; the floating glass: no).
    var takesKeyboardByItself = true
    private var granted = false

    /// The keyboard to the page, on DEXMA's own initiative (focusing it, a paste into it).
    func takeKeyboard() {
        granted = true
        defer { granted = false }
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        if !takesKeyboardByItself, !granted, !isClick(NSApp.currentEvent) { return false }
        return super.becomeFirstResponder()
    }

    /// A press of any mouse button in this view (a click into the page gives it the keyboard).
    private func isClick(_ event: NSEvent?) -> Bool {
        guard let event, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              event.window === window else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
