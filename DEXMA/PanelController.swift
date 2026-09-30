import AppKit
import Observation
import SwiftUI

enum PanelState {
    case closed
    /// Pointer hovering the notch: swollen slightly, a click opens.
    case peek
    case open
}

/// Single source of truth for the panel: `progress` (0 = notch, 1 = expanded) and state.
/// The hotkey, the gesture and the pointer all drive it; views only read it.
@Observable
final class PanelController {
    static let peekProgress: CGFloat = 0.06

    private(set) var progress: CGFloat = 0
    private(set) var state: PanelState = .closed
    private(set) var geometry: NotchGeometry

    @ObservationIgnored var escClosesPanel = true
    @ObservationIgnored var closesOnFocusLoss = true
    /// Open spring; close uses the same speed with no bounce so it settles fast.
    @ObservationIgnored var animationDuration: Double = 0.45
    @ObservationIgnored var bounce: Double = 0.2
    /// Asked for fresh geometry right before opening from fully closed (e.g. the pointer's
    /// screen), so the panel can move while it's invisible.
    @ObservationIgnored var geometryForOpening: (() -> NotchGeometry?)?

    private let panel: NotchPanel
    private let session: ShellSession
    private let driver: SpringDriver
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var interactionBase: CGFloat = 0

    init(panel: NotchPanel, session: ShellSession, geometry: NotchGeometry) {
        self.panel = panel
        self.session = session
        self.geometry = geometry
        driver = SpringDriver(window: panel)
        driver.onChange = { [weak self] value in self?.progress = value }
        driver.onRest = { [weak self] value in self?.didSettle(at: value) }
        panel.onEscape = { [weak self] in self?.handleEscape() ?? false }
        panel.onCloseShortcut = { [weak self] in self?.close() }
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        panel.onMouseDown = { [weak self] in self?.handleMouseDown() ?? false }
    }

    // MARK: Springs

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var openSpring: Spring {
        reduceMotion ? Spring(duration: 0.2, bounce: 0) : Spring(duration: animationDuration, bounce: bounce)
    }

    private var closeSpring: Spring {
        reduceMotion ? Spring(duration: 0.2, bounce: 0) : Spring(duration: animationDuration * 0.8, bounce: 0)
    }

    // MARK: Open / close

    func toggle() {
        if state == .open { close() } else { open() }
    }

    func open(initialVelocity: CGFloat? = nil) {
        if state != .open {
            moveToOpeningScreenIfClosed()
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost != NSRunningApplication.current { previousApp = frontmost }
            state = .open
            panel.ignoresMouseEvents = false
            // Key without activating DEXMA: the frontmost app keeps its menu bar, and
            // typing goes straight to the shell.
            panel.allowsKey = true
            session.container.isHidden = false
            panel.makeKey()
            panel.makeFirstResponder(session.terminalView)
        }
        driver.animate(to: 1, with: openSpring, initialVelocity: initialVelocity)
    }

    func close(initialVelocity: CGFloat? = nil) {
        if state != .closed {
            state = .closed
            // Click-through from the moment it starts closing, not when the animation ends.
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            restoreFocus()
        }
        driver.animate(to: 0, with: closeSpring, initialVelocity: initialVelocity)
    }

    /// Pointer entered or left the notch.
    func setHovering(_ hovering: Bool) {
        if hovering, state == .closed, progress < 0.2 {
            state = .peek
            panel.ignoresMouseEvents = false  // So the click that opens lands on us.
            driver.animate(to: Self.peekProgress, with: openSpring)
        } else if !hovering, state == .peek {
            state = .closed
            panel.ignoresMouseEvents = true
            driver.animate(to: 0, with: closeSpring)
        }
    }

    private func handleMouseDown() -> Bool {
        guard state == .peek else { return false }
        open()
        return true
    }

    // MARK: Interactive (gesture)

    /// Fingers took hold. Start from whatever is on screen, even mid-animation.
    func beginInteraction() {
        if state != .open { moveToOpeningScreenIfClosed() }
        interactionBase = progress
        session.container.isHidden = false
        driver.set(progress)
    }

    /// `delta`: progress change since `beginInteraction`, straight from the fingers (1:1).
    func updateInteraction(delta: CGFloat) {
        driver.set(Self.rubberBanded(interactionBase + delta))
    }

    /// Fingers lifted (or the gesture was cancelled, with zero velocity).
    func endInteraction(velocity: CGFloat) {
        // Where the panel would coast to in ~0.2 s decides the outcome, so a quick flick
        // opens or closes even from a short distance.
        let projected = progress + velocity * 0.2
        if projected > 0.5 {
            open(initialVelocity: velocity)
        } else {
            close(initialVelocity: velocity)
        }
    }

    /// Past either end the panel resists instead of stopping dead: 1 pt of finger → ~0.2 pt.
    private static func rubberBanded(_ value: CGFloat) -> CGFloat {
        if value > 1 { return 1 + min((value - 1) * 0.2, 0.08) }
        if value < 0 { return max(value * 0.2, -0.04) }
        return value
    }

    // MARK: Geometry

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
        panel.setFrame(newGeometry.panelFrame, display: true)
        session.resize(to: newGeometry.terminalFrame.size)
    }

    private func moveToOpeningScreenIfClosed() {
        guard progress <= Self.peekProgress + 0.01, let fresh = geometryForOpening?() else { return }
        updateGeometry(fresh)
    }

    #if DEBUG
    func debugJump(to value: CGFloat) {
        progress = value
    }
    #endif

    // MARK: Focus

    private func restoreFocus() {
        guard panel.isKeyWindow else { return }
        // A key non-activating panel still counts as "active" to AppKit; deactivating hands
        // the keyboard back to the frontmost app right away, not after the close animation.
        NSApp.deactivate()
        previousApp?.activate()
        previousApp = nil
    }

    private func didSettle(at value: CGFloat) {
        guard value == 0, state == .closed else { return }
        // Belt and braces: if the panel somehow kept key status, ordering it out drops it and
        // AppKit gives the keyboard back to the frontmost app. Closed, it's invisible anyway.
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        session.container.isHidden = true
    }

    private func handleEscape() -> Bool {
        // vim, less, htop… need Esc themselves.
        guard state == .open, escClosesPanel, !session.isRunningFullScreenProgram else {
            return false
        }
        close()
        return true
    }

    private func panelDidResignKey() {
        // The user clicked into another app: behave like Notification Center and get out of
        // the way (focus already went where they clicked).
        guard state == .open, closesOnFocusLoss else { return }
        previousApp = nil
        close()
    }
}
