import AppKit
import Observation
import SwiftUI

/// Single source of truth for the panel: `progress` (0 = notch, 1 = expanded) and state.
/// The hotkey, the gesture, the pointer and the menu bar item all drive it; views only read it.
@Observable
final class NotchViewModel: SwipeTarget, TabSwipeTarget {
    static let peekProgress: CGFloat = 0.06

    private(set) var progress: CGFloat = 0
    private(set) var state: PanelState = .closed
    private(set) var geometry: NotchGeometry
    /// The selected tab: it has the keyboard and the liquid effect pictures it.
    private(set) var tab: PanelTab = .terminal
    /// Where the pages, the selection indicator and the band's crossfade are: 0 = first tab;
    /// fractional during a swipe or a switch (its own spring), a little past either end while
    /// rubber-banding.
    private(set) var tabProgress: CGFloat = 0

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
    /// The Search tab: its card and the band's buttons.
    let search: SearchViewModel
    /// The content card's pages, one per tab.
    let pager: ContentPagerView
    @ObservationIgnored var gestureTuning = GestureTuning.standard
    private let panel: NotchPanel
    private let driver: SpringDriver
    private let tabDriver: SpringDriver
    private let tabSwipes: TabSwipeMonitor
    private let motion: LiquidMotionEngine
    @ObservationIgnored private var swipeBase: CGFloat = 0
    @ObservationIgnored private var swipeStart = 0
    private let focus = FocusHandoff()
    @ObservationIgnored private var interactionBase: CGFloat = 0
    /// Where letting go of the swipe would end up (open = true), for the threshold haptic.
    @ObservationIgnored private var releaseOpens = false
    /// The current open/close came from a swipe: tick when it lands.
    @ObservationIgnored private var ticksOnLanding = false

    init(panel: NotchPanel, session: ShellSession, search: SearchViewModel, pager: ContentPagerView,
         geometry: NotchGeometry) {
        self.panel = panel
        self.session = session
        self.search = search
        self.pager = pager
        self.geometry = geometry
        let driver = SpringDriver(window: panel)
        self.driver = driver
        let tabDriver = SpringDriver(window: panel)
        tabDriver.runsWhileHeld = true  // The indicator's stretch follows the fingers too.
        self.tabDriver = tabDriver
        tabSwipes = TabSwipeMonitor(panel: panel)
        motion = LiquidMotionEngine(content: session, driver: driver)
        motion.peekProgress = Self.peekProgress
        driver.onChange = { [weak self] value in self?.progress = value }
        driver.onRest = { [weak self] value in self?.didSettle(at: value) }
        driver.onArrive = { [weak self] target, velocity in self?.didArrive(at: target, velocity: velocity) }
        driver.onFrame = { [weak self] dt in self?.stepEffects(dt) ?? false }
        session.onOutput = { [weak self] in
            guard let self else { return }
            motion.contentDidChange(self.session)
        }
        search.session.onChange = { [weak self] in
            guard let self else { return }
            motion.contentDidChange(self.search.session)
        }
        panel.onInput = { [weak self] type in self?.motion.contentReceived(type) }
        panel.onEscape = { [weak self] in self?.handleEscape() ?? false }
        panel.onCloseShortcut = { [weak self] in self?.close() }
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
        panel.onMouseDown = { [weak self] in self?.handleMouseDown() ?? false }
        panel.onCommandKey = { [weak self] key in self?.handleCommandKey(key) ?? false }
        tabDriver.onChange = { [weak self] value in self?.tabProgressChanged(value) }
        tabDriver.onArrive = { [weak self] _, velocity in self?.band.landIndicator(velocity: velocity) }
        tabDriver.onFrame = { [weak self, weak tabDriver] dt in
            self?.band.stepIndicator(dt: dt, velocity: tabDriver?.screenVelocity ?? 0) ?? false
        }
        pager.setPages([session.container, search.session.card])
        tabSwipes.target = self
        tabSwipes.start()
    }

    // MARK: Liquid effect settings

    /// Liquid effect strength, 0 (off: the live content animates, as it always did) … 1.
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

    /// The band's liquid controls and selection indicator; the band's views render them.
    var band: BandMotion { motion.band }

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
            // typing goes straight to the selected tab.
            panel.allowsKey = true
            pager.isShowingPages = true
            panel.makeKey()
            focusSelectedTab()
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
        settleTabsNow()
        if progress != 0 { motion.begin() }
        if state != .closed {
            if state == .open, tab == .search { search.session.rememberFocus(in: panel) }
            band.releaseAll()
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
            // The swell is liquid too: a breath, the jelly, and the screen pushed out.
            if motion.begin(), progress <= 0.01 { effects.anticipate() }
            driver.animate(to: Self.peekProgress, with: openSpring)
        } else if !hovering, state == .peek {
            state = .closed
            panel.ignoresMouseEvents = true
            motion.begin()
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
    /// scrolls it) and isn't running a full-screen program; the Search page shows its end.
    var canCloseBySwipe: Bool {
        switch tab {
        case .terminal: session.isScrolledToBottom && !session.isRunningFullScreenProgram
        case .search: search.session.isScrolledToBottom
        }
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
        pager.isShowingPages = true
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
        session.resize(to: newGeometry.contentFrame.size)
        search.session.resize(to: newGeometry.contentFrame.size)
        pager.resize(to: newGeometry.contentFrame.size)
        // Resized: the cached snapshots no longer fit.
        motion.contentDidChange(session)
        motion.contentDidChange(search.session)
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

    // MARK: Tabs

    private var tabSpring: Spring {
        reduceMotion ? Spring(duration: 0.2, bounce: 0) : Spring(duration: 0.4, bounce: 0.15)
    }

    private func index(of tab: PanelTab) -> Int {
        PanelTab.allCases.firstIndex(of: tab) ?? 0
    }

    /// Shows `newTab` (clicked, or ⌘-number): the pages, indicator and band slide there on the
    /// tab spring (jump with Reduce Motion) and it gets the keyboard if open.
    func select(_ newTab: PanelTab) {
        commit(newTab)
        let target = CGFloat(index(of: newTab))
        if reduceMotion || state != .open {
            tabDriver.set(target)
        } else {
            tabDriver.animate(to: target, with: tabSpring)
        }
    }

    /// `newTab` becomes the selected tab: keyboard and liquid effect. Its page is already on
    /// the card or sliding in; the old one hides once it has slid off (`ContentPagerView`).
    private func commit(_ newTab: PanelTab) {
        guard newTab != tab else { return }
        tab = newTab
        if state == .open { focusSelectedTab() }
        motion.setContent(newTab == .terminal ? session : search.session)
    }

    private func tabProgressChanged(_ value: CGFloat) {
        tabProgress = value
        pager.setProgress(value)
    }

    /// Before closing: no half-swiped pages; the selected tab snaps into place (the liquid
    /// effect pictures it alone).
    private func settleTabsNow() {
        let target = CGFloat(index(of: tab))
        if tabProgress != target || tabDriver.isAnimating { tabDriver.set(target) }
    }

    // MARK: TabSwipeTarget

    var acceptsTabSwipes: Bool { state == .open }

    var tabPageWidth: CGFloat { geometry.contentFrame.width }

    func canSwipeTabs(at point: CGPoint, direction: Int) -> Bool {
        let body = geometry.shape(at: 1)
        let band = CGRect(x: body.centerX - body.width / 2, y: 0, width: body.width, height: geometry.bandHeight)
        if band.contains(point) { return true }
        guard geometry.contentFrame.contains(point) else { return false }
        switch tab {
        case .terminal: return true
        // Only where the page can't scroll further sideways itself (most pages never can).
        case .search: return !search.session.canScrollHorizontally(toward: direction)
        }
    }

    func beginTabSwipe() {
        swipeBase = tabProgress
        swipeStart = Int(tabProgress.rounded())
        tabDriver.set(tabProgress)
    }

    func updateTabSwipe(delta: CGFloat) {
        guard state == .open else { return }
        tabDriver.set(rubberBanded(swipeBase + delta))
    }

    /// Past `commitFraction` of a page, or flicked faster than `flickVelocity`, it goes on to
    /// the next tab that way; otherwise back. The spring takes the fingers' speed.
    func endTabSwipe(delta: CGFloat, velocity: CGFloat) {
        guard state == .open else { return }
        let last = PanelTab.allCases.count - 1
        let raw = swipeBase + delta
        let moved = raw - CGFloat(swipeStart)
        var target = swipeStart
        if abs(moved) >= 1 {
            target = Int(raw.rounded())
        } else if moved > gestureTuning.commitFraction || velocity > gestureTuning.flickVelocity {
            target = swipeStart + 1
        } else if moved < -gestureTuning.commitFraction || velocity < -gestureTuning.flickVelocity {
            target = swipeStart - 1
        }
        target = min(max(target, 0), last)
        let newTab = PanelTab.allCases[target]
        if newTab != tab {
            Haptics.tap()
            commit(newTab)
        }
        tabDriver.animate(to: CGFloat(target), with: tabSpring, initialVelocity: velocity)
    }

    /// Past the first and last tab the pages resist: a fraction of the fingers, up to a limit.
    private func rubberBanded(_ value: CGFloat) -> CGFloat {
        let last = CGFloat(PanelTab.allCases.count - 1)
        let t = gestureTuning
        if value < 0 { return -min(-value * t.rubberBand, t.rubberBandLimit) }
        if value > last { return last + min((value - last) * t.rubberBand, t.rubberBandLimit) }
        return value
    }

    /// A click on one of the band's controls: a light tick, then its action.
    func click(_ action: () -> Void) {
        Haptics.tap()
        action()
    }

    private func focusSelectedTab() {
        switch tab {
        case .terminal: panel.makeFirstResponder(session.terminalView)
        case .search: search.session.restoreFocus()
        }
    }

    /// ⌘1/⌘2 pick a tab, ⌘L goes to the search field; ⌘[ ⌘] ⌘R browse on the Search tab.
    private func handleCommandKey(_ key: String) -> Bool {
        guard state == .open else { return false }
        switch key {
        case "1": select(.terminal)
        case "2": select(.search)
        case "l":
            select(.search)
            search.session.focusField()
        case "[" where tab == .search: search.goBack()
        case "]" where tab == .search: search.goForward()
        case "r" where tab == .search: search.reloadOrStop()
        default: return false
        }
        return true
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
        pager.isShowingPages = false
    }

    private func handleEscape() -> Bool {
        // vim, less, htop… need Esc themselves.
        guard state == .open, escClosesPanel,
              !(tab == .terminal && session.isRunningFullScreenProgram) else {
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
    var debugTabDriver: SpringDriver { tabDriver }
    #endif
}
