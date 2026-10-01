import AppKit
import Observation
import SwiftUI

/// Single source of truth for the panel: `progress` (0 = notch, 1 = expanded) and state.
/// The hotkey, the gesture, the pointer and the menu bar item all drive it; views only read it.
@Observable
final class NotchViewModel: SwipeTarget {
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

    /// The one terminal, shown in the panel.
    let session: ShellSession
    private let panel: NotchPanel
    private let driver: SpringDriver
    private let motion: LiquidMotionEngine
    private let focus = FocusHandoff()
    @ObservationIgnored private var interactionBase: CGFloat = 0
    /// Where letting go of the swipe would end up (open = true), for the threshold haptic.
    @ObservationIgnored private var releaseOpens = false
    /// The current open/close came from a swipe: tick when it lands.
    @ObservationIgnored private var ticksOnLanding = false

    init(panel: NotchPanel, session: ShellSession, geometry: NotchGeometry) {
        self.panel = panel
        self.session = session
        self.geometry = geometry
        let driver = SpringDriver(window: panel)
        self.driver = driver
        motion = LiquidMotionEngine(session: session, driver: driver)
        driver.onChange = { [weak self] value in self?.progress = value }
        driver.onRest = { [weak self] value in self?.didSettle(at: value) }
        driver.onArrive = { [weak self] target, velocity in self?.didArrive(at: target, velocity: velocity) }
        driver.onFrame = { [weak self] dt in self?.stepEffects(dt) ?? false }
        session.onOutput = { [weak self] in self?.motion.terminalDidChange() }
        panel.onInput = { [weak self] type in self?.motion.terminalReceived(type) }
        panel.onEscape = { [weak self] in self?.handleEscape() ?? false }
        panel.onCloseShortcut = { [weak self] in self?.close() }
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        panel.onMouseDown = { [weak self] in self?.handleMouseDown() ?? false }
    }

    // MARK: Liquid effect settings

    /// Liquid effect strength, 0 (off: the live terminal animates, as it always did) … 1.
    var effectIntensity: CGFloat {
        get { motion.intensity }
        set { motion.intensity = newValue }
    }

    /// Bends the real screen around the notch while it moves and near the pointer.
    var bender: ScreenBender? {
        get { motion.bender }
        set {
            motion.bender = newValue
            newValue?.allowsPointer = { [weak self] in self?.state != .open && !(self?.reduceMotion ?? true) }
        }
    }

    /// The liquid effect's per-frame state; the content view renders it.
    var effects: MotionEffects { motion.effects }

    // MARK: Presentation

    /// The silhouette as drawn this frame: squashed and stretched by the liquid effect
    /// (exactly 1 × 1 at rest).
    var silhouette: Silhouette {
        effects.frame.silhouette(in: geometry, at: progress)
    }

    /// Text fades in once the silhouette is mostly open, so it never floats in a sliver.
    var contentOpacity: CGFloat {
        min(max((progress - 0.35) / 0.5, 0), 1)
    }

    /// Where the pointer counts as over the notch (global coordinates); it follows the state.
    var hoverZone: CGRect {
        geometry.hoverZone(peeking: state == .peek)
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

    var isOpen: Bool { state == .open }

    func toggle() {
        if state == .open { close() } else { open() }
    }

    func open(initialVelocity: CGFloat? = nil, fromGesture: Bool = false) {
        if state != .open {
            let fromClosed = progress <= Self.peekProgress + 0.01
            moveToOpeningScreenIfClosed()
            focus.rememberFrontmostApp()
            state = .open
            panel.ignoresMouseEvents = false
            // Key without activating DEXMA: the frontmost app keeps its menu bar, and
            // typing goes straight to the shell.
            panel.allowsKey = true
            session.container.isHidden = false
            panel.makeKey()
            panel.makeFirstResponder(session.terminalView)
            // After focusing, so a fresh snapshot shows the caret the live view will have.
            if motion.begin(), fromClosed { effects.anticipate() }
        } else if progress != 1 {
            motion.begin()
        }
        ticksOnLanding = fromGesture
        driver.animate(to: 1, with: openSpring, initialVelocity: initialVelocity)
    }

    func close(initialVelocity: CGFloat? = nil, fromGesture: Bool = false) {
        // Before focus leaves: the snapshot must match the frame on screen right now.
        if progress != 0 { motion.begin() }
        if state != .closed {
            state = .closed
            // Click-through from the moment it starts closing, not when the animation ends.
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            focus.returnFocus(from: panel)
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

    /// A swipe up may close it: the terminal shows its newest output (otherwise the swipe
    /// scrolls it) and isn't running a full-screen program.
    var canCloseBySwipe: Bool {
        session.isScrolledToBottom && !session.isRunningFullScreenProgram
    }

    /// Fingers landed where a swipe starts: get the screen warp's capture going early.
    func prepareForMotion() {
        motion.prepare()
    }

    /// Fingers took hold. Start from whatever is on screen, even mid-animation.
    func beginInteraction() {
        let fromClosed = state != .open && progress <= Self.peekProgress + 0.01
        if state != .open { moveToOpeningScreenIfClosed() }
        interactionBase = progress
        session.container.isHidden = false
        if motion.begin(), fromClosed {
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
        motion.terminalDidChange()  // Resized: the cached snapshot no longer fits.
    }

    private func moveToOpeningScreenIfClosed() {
        guard progress <= Self.peekProgress + 0.01, let fresh = geometryForOpening?() else { return }
        updateGeometry(fresh)
    }

    // MARK: Liquid effect

    /// Every display frame, once the spring has stepped.
    private func stepEffects(_ dt: CFTimeInterval) -> Bool {
        motion.step(dt: dt, progress: progress, geometry: geometry, isOpen: state == .open)
    }

    private func didArrive(at target: CGFloat, velocity: CGFloat) {
        guard target == 0 || target == 1 else { return }  // Not for peeking.
        motion.land(velocity: velocity)
        if ticksOnLanding {
            ticksOnLanding = false
            Haptics.snap()
        }
    }

    /// Renders the motion layer once at launch (closed, zero effect: it looks exactly like the
    /// notch) so its shaders are compiled before the first real open.
    func warmUpEffects() {
        guard state == .closed else { return }
        motion.warmUp()
    }

    // MARK: Focus

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
        focus.forget()
        close()
    }

    // MARK: Debug

    #if DEBUG
    func debugJump(to value: CGFloat) {
        progress = value
    }

    /// Puts the motion layer up (fresh snapshot) without moving, as at the start of a motion,
    /// and keeps it up until `debugEndMotion`.
    func debugBeginMotion() {
        motion.debugBegin()
    }

    func debugEndMotion() {
        motion.debugEnd(isOpen: state == .open)
    }

    /// Freezes the panel at `progress` with the given effect values, for visual checks.
    func debugPose(progress value: CGFloat, effect: MotionEffects.Frame) {
        progress = value
        motion.debugPose(effect, progress: value, geometry: geometry)
    }

    var debugDriver: SpringDriver { driver }
    #endif
}
