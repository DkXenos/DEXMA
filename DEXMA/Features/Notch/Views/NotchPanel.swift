import AppKit
import Carbon.HIToolbox

/// Borderless, transparent, non-activating panel that sits over the notch on every Space.
///
/// Non-activating means it can become key (and take typing) without activating DEXMA, so
/// the app you were in stays frontmost and gets the keyboard back as soon as the panel closes.
final class NotchPanel: NSPanel {
    /// Only true while open; a closed panel must never steal the keyboard.
    var allowsKey = false
    /// Esc pressed while key. Return true if handled.
    var onEscape: (() -> Bool)?
    var onCloseShortcut: (() -> Void)?
    var onResignKey: (() -> Void)?
    /// A click on the panel while it's not taking mouse input for the terminal (peek state).
    var onMouseDown: (() -> Bool)?
    /// Typing, clicking, dragging or scrolling reached the panel: what the selected tab shows
    /// may have changed.
    var onInput: ((NSEvent.EventType) -> Void)?
    /// Any other ⌘-key (the key without modifiers, lowercased). Return true if handled.
    var onCommandKey: ((String) -> Bool)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The window server would recompute a shadow for the changing shape every frame.
        hasShadow = false
        // Window levels: menu bar = 24, status items/Control Center = 25, pop-up menus = 101.
        // One above the status items lets the expanded panel cover the menu bar, while menus
        // opened from the menu bar still draw on top of it.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,           // Doesn't move or hide in Mission Control / Space switches.
            .fullScreenAuxiliary,  // Allowed over full-screen apps.
            .ignoresCycle,         // Not part of ⌘` window cycling.
        ]
        hidesOnDeactivate = false  // NSPanel defaults to true; an agent app is rarely active.
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true  // Closed: fully click-through.
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // AppKit keeps windows below the menu bar; this one must overlap it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == UInt16(kVK_Escape)
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
            if onEscape?() == true { return }
        case .leftMouseDown:
            if onMouseDown?() == true { return }
        default:
            break
        }
        super.sendEvent(event)
        switch event.type {
        case .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown,
             .otherMouseDown, .scrollWheel:
            onInput?(event.type)
        default:
            break
        }
    }

    // Key equivalents reach the key window before any menu. A key panel of an inactive agent
    // app gets no Edit menu, so the basics are routed to the first responder (terminal, search
    // field or page) here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "w":
            onCloseShortcut?()
            return true
        case "q":
            return true  // Quitting would kill the shell; quit from the menu bar item instead.
        default:
            if onCommandKey?(key) == true { return true }
            return super.performKeyEquivalent(with: event)
        }
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
