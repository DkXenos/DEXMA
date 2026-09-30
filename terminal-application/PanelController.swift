import AppKit
import Observation
import SwiftUI

enum PanelState {
    case closed
    case open
}

/// Single source of truth for the panel: `progress` (0 = notch, 1 = expanded) and state.
/// The hotkey (and, from Phase 5, the gesture) drive it; views only read it.
@Observable
final class PanelController {
    // Open with a slight Dynamic Island overshoot; close without bounce so it settles fast.
    static let openSpring = Spring(duration: 0.45, bounce: 0.2)
    static let closeSpring = Spring(duration: 0.35, bounce: 0)

    private(set) var progress: CGFloat = 0
    private(set) var state: PanelState = .closed
    private(set) var geometry: NotchGeometry

    @ObservationIgnored var escClosesPanel = true
    @ObservationIgnored var closesOnFocusLoss = true

    private let panel: NotchPanel
    private let session: ShellSession
    private let driver: SpringDriver
    @ObservationIgnored private var previousApp: NSRunningApplication?

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
    }

    func toggle() {
        if state == .open { close() } else { open() }
    }

    func open(initialVelocity: CGFloat? = nil) {
        if state != .open {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost != NSRunningApplication.current { previousApp = frontmost }
            state = .open
            panel.ignoresMouseEvents = false
            // Key without activating NotchTerm: the frontmost app keeps its menu bar, and
            // typing goes straight to the shell.
            panel.allowsKey = true
            session.container.isHidden = false
            panel.makeKey()
            panel.makeFirstResponder(session.terminalView)
        }
        driver.animate(to: 1, with: Self.openSpring, initialVelocity: initialVelocity)
    }

    func close(initialVelocity: CGFloat? = nil) {
        if state != .closed {
            state = .closed
            // Click-through from the moment it starts closing, not when the animation ends.
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            restoreFocus()
        }
        driver.animate(to: 0, with: Self.closeSpring, initialVelocity: initialVelocity)
    }

    // MARK: Interactive (gesture)

    @ObservationIgnored private var interactionBase: CGFloat = 0

    /// Fingers took hold. Start from whatever is on screen, even mid-animation.
    func beginInteraction() {
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

    #if DEBUG
    func debugJump(to value: CGFloat) {
        progress = value
    }
    #endif

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
        panel.setFrame(newGeometry.panelFrame, display: true)
        session.resize(to: newGeometry.terminalFrame.size)
    }

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
        // Belt and braces: if the panel somehow kept key status, ordering it out drops it and
        // AppKit gives the keyboard back to the frontmost app. Closed, it's invisible anyway.
        guard value == 0, state == .closed, !driver.isAnimating else { return }
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
