import AppKit
import Carbon.HIToolbox

/// The borderless window covering one whole display in capture mode: above everything,
/// including the menu bar, the notch panel and full-screen apps, on the current Space. It takes
/// the keyboard (for Esc) without activating DEXMA, like the notch panel, so the app you were in
/// stays frontmost.
final class CaptureOverlayPanel: NSPanel {
    var onEscape: (() -> Void)?
    let overlay: CaptureOverlayView

    init() {
        overlay = CaptureOverlayView(frame: .zero)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Window levels: menu bar 24, status items 25, the notch panel 26, pop-up menus 101; the
        // screen saver level (1000) is above them all.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit keeps windows below the menu bar; this one covers it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    /// Esc may also come as the cancel action (e.g. ⌘.).
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
