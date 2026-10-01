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
    /// Liquid effect strength, 0 (off: the live terminal animates, as it always did) … 1.
    @ObservationIgnored var effectIntensity: CGFloat = 1 {
        didSet { effects.tuning = EffectTuning.full.scaled(by: effectIntensity) }
    }

    /// The liquid effect's per-frame state; the content view renders it.
    let effects = MotionEffects()
    /// Bends the screen around the silhouette while it moves (macOS 26).
    @ObservationIgnored var backdrop: BackdropLens?

    private let panel: NotchPanel
    private let session: ShellSession
    private let driver: SpringDriver
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var interactionBase: CGFloat = 0
    /// Where letting go of the swipe would end up (open = true), for the threshold haptic.
    @ObservationIgnored private var releaseOpens = false
    /// The current open/close came from a swipe: tick when it lands.
    @ObservationIgnored private var ticksOnLanding = false
    @ObservationIgnored private var snapshotRefreshPending = false
    @ObservationIgnored private var lastTerminalChange: CFTimeInterval = 0
    #if DEBUG
    @ObservationIgnored private var debugHoldsMotion = false
    #else
    private let debugHoldsMotion = false
    #endif

    init(panel: NotchPanel, session: ShellSession, geometry: NotchGeometry) {
        self.panel = panel
        self.session = session
        self.geometry = geometry
        driver = SpringDriver(window: panel)
        driver.onChange = { [weak self] value in self?.progress = value }
        driver.onRest = { [weak self] value in self?.didSettle(at: value) }
        driver.onArrive = { [weak self] target, velocity in self?.didArrive(at: target, velocity: velocity) }
        driver.onFrame = { [weak self] dt in self?.stepEffects(dt) ?? false }
        session.onOutput = { [weak self] in self?.terminalDidChange() }
        panel.onInput = { [weak self] type in self?.terminalReceived(type) }
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

    func open(initialVelocity: CGFloat? = nil, fromGesture: Bool = false) {
        if state != .open {
            let fromClosed = progress <= Self.peekProgress + 0.01
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
            // After focusing, so a fresh snapshot shows the caret the live view will have.
            if beginMotion(), fromClosed { effects.anticipate() }
        } else if progress != 1 {
            beginMotion()
        }
        ticksOnLanding = fromGesture
        driver.animate(to: 1, with: openSpring, initialVelocity: initialVelocity)
    }

    func close(initialVelocity: CGFloat? = nil, fromGesture: Bool = false) {
        // Before focus leaves: the snapshot must match the frame on screen right now.
        if progress != 0 { beginMotion() }
        if state != .closed {
            state = .closed
            // Click-through from the moment it starts closing, not when the animation ends.
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            restoreFocus()
        }
        ticksOnLanding = fromGesture
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
        let fromClosed = state != .open && progress <= Self.peekProgress + 0.01
        if state != .open { moveToOpeningScreenIfClosed() }
        interactionBase = progress
        session.container.isHidden = false
        if beginMotion(), fromClosed {
            effects.anticipate()
        }
        releaseOpens = progress > 0.5
        driver.runsWhileHeld = effects.isActive
        driver.set(progress)
    }

    /// `delta`: progress change since `beginInteraction`, straight from the fingers (1:1).
    func updateInteraction(delta: CGFloat) {
        let value = Self.rubberBanded(interactionBase + delta)
        // A tick as the swipe passes the point of no return, either way (with a little
        // hysteresis so a finger resting on the line doesn't buzz).
        if releaseOpens ? value < 0.48 : value > 0.52 {
            releaseOpens.toggle()
            Haptics.threshold()
        }
        driver.set(value)
    }

    /// Fingers lifted (or the gesture was cancelled, with zero velocity).
    func endInteraction(velocity: CGFloat) {
        // Where the panel would coast to in ~0.2 s decides the outcome, so a quick flick
        // opens or closes even from a short distance.
        let projected = progress + velocity * 0.2
        if projected > 0.5 {
            open(initialVelocity: velocity, fromGesture: true)
        } else {
            close(initialVelocity: velocity, fromGesture: true)
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
        terminalDidChange()  // Resized: the cached snapshot no longer fits.
    }

    private func moveToOpeningScreenIfClosed() {
        guard progress <= Self.peekProgress + 0.01, let fresh = geometryForOpening?() else { return }
        updateGeometry(fresh)
    }

    #if DEBUG
    func debugJump(to value: CGFloat) {
        progress = value
    }

    /// Puts the motion layer up (fresh snapshot) without moving, as at the start of a motion,
    /// and keeps it up until `debugEndMotion`.
    func debugBeginMotion() {
        debugHoldsMotion = true
        session.invalidateSnapshot()
        beginMotion()
    }

    func debugEndMotion() {
        debugHoldsMotion = false
        endMotion()
    }

    /// Freezes the panel at `progress` with the given effect values, for visual checks.
    func debugPose(progress value: CGFloat, effect: MotionEffects.Frame) {
        progress = value
        effects.debugSet(effect)
        updateBackdrop()
    }

    var debugDriver: SpringDriver { driver }
    #endif

    // MARK: Liquid effect

    /// The effect is skipped entirely with Reduce Motion or the intensity slider at Off.
    private var effectsEnabled: Bool {
        !reduceMotion && effects.tuning.isVisible
    }

    /// Swaps the live terminal for its snapshot so the shaders can bend it. Returns whether
    /// the motion layer is up. The snapshot is normally one taken while idle
    /// (`scheduleIdleSnapshot`); only a change in the last half second means taking one now,
    /// a few ms before the first frame.
    @discardableResult
    private func beginMotion() -> Bool {
        if effects.isActive {
            // Up already (mid-flight, or the launch warm-up): keep its snapshot if it has one.
            if effects.snapshot == nil { effects.begin(with: session.snapshot()) }
            return true
        }
        guard effectsEnabled else { return false }
        effects.begin(with: session.snapshot())
        return true
    }

    private func stepEffects(_ dt: CFTimeInterval) -> Bool {
        guard effects.isActive else { return false }
        let moving = effects.step(dt: dt, velocity: driver.screenVelocity)
        if !moving, !driver.isSpringing, !driver.isHeld, !debugHoldsMotion {
            endMotion()
        }
        updateBackdrop()
        return moving
    }

    /// The glass ring follows the silhouette as drawn this frame, as wide as the motion is
    /// strong (speed, peaking mid-way, or the anticipation swell); gone at rest.
    private func updateBackdrop() {
        guard let backdrop else { return }
        let frame = effects.frame
        let tuning = effects.tuning
        let base = geometry.shape(at: progress)
        let shape = base.scaled(by: frame.scale(width: base.width, height: base.height))
        let p = min(max(progress, 0), 1)
        let swell = tuning.anticipation > 0 ? frame.bulge / tuning.anticipation : 0
        let strength = min(max(frame.energy * (0.4 + 0.6 * sin(.pi * p)), swell), 1)
        backdrop.update(
            silhouette: CGRect(x: shape.centerX - shape.width / 2, y: 0,
                               width: shape.width, height: shape.height),
            radius: shape.drawnBottomRadius,
            ring: effects.isActive ? tuning.backdropRing * strength : 0)
    }

    /// Everything is at rest and every effect is exactly zero: the live terminal comes back
    /// in the same frame the motion layer goes (both are SwiftUI state in one update).
    private func endMotion() {
        effects.end()
        updateBackdrop()  // Hides the glass.
        if state == .open {
            session.restartCaretBlink()
            // Taken while closed (no caret): retake it with the caret before the next close.
            if session.snapshotMissesCaret { terminalDidChange() }
        }
        scheduleIdleSnapshot()
    }

    private func didArrive(at target: CGFloat, velocity: CGFloat) {
        guard target == 0 || target == 1 else { return }  // Not for peeking.
        if effects.isActive { effects.land(velocity: velocity) }
        if ticksOnLanding {
            ticksOnLanding = false
            Haptics.snap()
        }
    }

    private func terminalReceived(_ type: NSEvent.EventType) {
        // Scroll events also arrive during a close swipe, with nothing left to scroll:
        // only an actual scroll makes the snapshot stale.
        if type == .scrollWheel, !session.snapshotScrolledAway { return }
        terminalDidChange()
    }

    /// The terminal may look different now (output, typing, a click, drag or scroll, a
    /// resize): the cached snapshot is stale.
    private func terminalDidChange() {
        session.invalidateSnapshot()
        lastTerminalChange = CACurrentMediaTime()
        scheduleIdleSnapshot()
    }

    /// Takes the next snapshot once the terminal has been quiet for half a second and the
    /// panel is at rest, so opening and closing find one ready and do no work up front.
    private func scheduleIdleSnapshot() {
        guard effectsEnabled, !snapshotRefreshPending else { return }
        snapshotRefreshPending = true
        let quiet: CFTimeInterval = 0.5
        let wait = max(quiet - (CACurrentMediaTime() - lastTerminalChange), 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.snapshotRefreshPending = false
            if CACurrentMediaTime() - self.lastTerminalChange < quiet {
                self.scheduleIdleSnapshot()  // Still busy: look again later.
                return
            }
            // Mid-motion the snapshot on screen is in use; `endMotion` asks again at rest.
            guard !self.driver.isAnimating, !self.driver.isHeld, !self.effects.isActive else { return }
            _ = self.session.snapshot()
        }
    }

    /// Renders the motion layer once at launch (closed, zero effect: it looks exactly like the
    /// notch) so its shaders are compiled before the first real open.
    func warmUpEffects() {
        guard !effects.isActive, state == .closed, !driver.isAnimating else { return }
        let notch = geometry.shape(at: 0)
        backdrop?.warmUp(behind: CGRect(x: notch.centerX - notch.width / 2, y: 0,
                                        width: notch.width, height: notch.height))
        effects.begin(with: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.effects.isActive, !self.driver.isAnimating, !self.driver.isHeld else { return }
            self.effects.end()
        }
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
