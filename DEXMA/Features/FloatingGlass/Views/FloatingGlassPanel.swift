import AppKit
import Carbon.HIToolbox

/// A Spotlight-style floating window, for any content: borderless and transparent (the content
/// draws its glass shapes), takes the keyboard without activating DEXMA (no Dock icon; the app the
/// user was in stays frontmost and gets the keyboard back), above normal windows on every Space
/// and over full-screen apps. Never closed: ordered out while hidden, so its views (and a web
/// view) stay alive.
final class FloatingGlassPanel: NSPanel {
    /// Only while shown: a hidden panel never takes the keyboard.
    var allowsKey = false
    /// Esc, unmodified. Return true if handled.
    var onEscape: (() -> Bool)?
    var onResignKey: (() -> Void)?
    /// Any key equivalent the panel doesn't route itself (⌘-keys, ⌘↓…). Return true if handled.
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own shadow; a window shadow would double it (and be recomputed for
        // every frame of a morph).
        hasShadow = false
        // Window levels: normal 0, floating 3, modal panels 8, menu bar 24, the notch 26, its
        // sign-in popups 27. Above normal and floating windows, below the menu bar and the
        // sign-in popups (which claude.ai opens from this window).
        level = .modalPanel
        collectionBehavior = [
            .canJoinAllSpaces,     // Comes up on whichever Space is active.
            .fullScreenAuxiliary,  // Allowed over full-screen apps.
            .transient,            // Not in Mission Control or Exposé.
            .ignoresCycle,         // Not part of ⌘` window cycling.
        ]
        hidesOnDeactivate = false  // NSPanel defaults to true; an agent app is rarely active.
        animationBehavior = .none  // The content animates itself.
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, onEscape?() == true {
            return
        }
        super.sendEvent(event)
    }

    // A key panel of an inactive agent app gets no Edit menu: the basics go to the first
    // responder (the field, or the page) from here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased() {
            let selector: Selector? = switch (key, flags == .command) {
            case ("c", true): #selector(NSText.copy(_:))
            case ("v", true): #selector(NSText.paste(_:))
            case ("x", true): #selector(NSText.cut(_:))
            case ("a", true): #selector(NSText.selectAll(_:))
            case ("z", true): Selector(("undo:"))
            case ("z", false): Selector(("redo:"))
            default: nil
            }
            if let selector { return NSApp.sendAction(selector, to: nil, from: self) }
            if key == "q", flags == .command { return true }  // Quitting would end the terminal's shell.
        }
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
