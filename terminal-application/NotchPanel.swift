import AppKit

/// Borderless, transparent, non-activating panel that sits over the notch on every Space.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The window server would recompute a shadow for the changing shape every frame;
        // the shape draws its own shadow instead (Phase 2).
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

    // AppKit keeps windows below the menu bar; this one must overlap it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
