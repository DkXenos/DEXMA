import AppKit

/// Runs the liquid effect around every motion of the panel. While the panel moves, a snapshot
/// of the selected tab's content stands in for the live view (so the motion layer's shaders
/// can bend it), and `MotionEffects` and the screen bend are stepped every display frame; the
/// live content comes back once everything is exactly at rest. Between motions a fresh snapshot is kept
/// ready, so opening and closing normally capture nothing.
final class LiquidMotionEngine {
    /// The effect's per-frame state; the motion layer renders it.
    let effects = MotionEffects()
    /// Bends the real screen around the silhouette while it moves and near the pointer.
    var bender: ScreenBender? {
        didSet {
            bender?.tuning = effects.tuning
            bender?.wake = { [weak self] in self?.driver.wake() }
        }
    }
    /// 0 (off: the live content animates, as it always did) … 1 (`EffectTuning.full`).
    var intensity: CGFloat = 1 {
        didSet {
            effects.tuning = EffectTuning.full.scaled(by: intensity)
            bender?.tuning = effects.tuning
        }
    }

    /// The selected tab's content: what the snapshot pictures.
    private(set) var content: MotionContent
    private let driver: SpringDriver
    private var snapshotRefreshPending = false
    private var lastContentChange: CFTimeInterval = 0
    #if DEBUG
    private var debugHoldsMotion = false
    #else
    private let debugHoldsMotion = false
    #endif

    init(content: MotionContent, driver: SpringDriver) {
        self.content = content
        self.driver = driver
        content.onSnapshotRefreshed = { [weak self] in self?.snapshotRefreshed() }
    }

    /// Another tab was selected. Mid-motion its picture takes over right away (a quick capture
    /// on a user's tab switch); at rest the next idle snapshot is of the new content.
    func setContent(_ newContent: MotionContent) {
        guard newContent !== content else { return }
        content.onSnapshotRefreshed = nil
        content = newContent
        newContent.onSnapshotRefreshed = { [weak self] in self?.snapshotRefreshed() }
        if effects.isActive { effects.show(newContent.motionSnapshot()) }
        lastContentChange = CACurrentMediaTime()
        scheduleIdleSnapshot()
    }

    /// The effect is skipped entirely with Reduce Motion or the intensity slider at Off.
    var isEnabled: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && effects.tuning.isVisible
    }

    /// Swaps the live content for its snapshot so the shaders can bend it. Returns whether
    /// the motion layer is up. The snapshot is normally one taken while idle
    /// (`scheduleIdleSnapshot`); only a change in the last half second means taking one now,
    /// a few ms before the first frame.
    @discardableResult
    func begin() -> Bool {
        if effects.isActive {
            // Up already (mid-flight, or the launch warm-up): keep its snapshot if it has one.
            if effects.snapshot == nil { effects.begin(with: content.motionSnapshot()) }
            return true
        }
        guard isEnabled else { return false }
        bender?.prepare()
        effects.begin(with: content.motionSnapshot())
        return true
    }

    /// A motion may be about to start (fingers on the trackpad's top edge): get the screen
    /// warp's capture going early.
    func prepare() {
        guard isEnabled else { return }
        bender?.prepare()
    }

    /// One display frame, after the spring has stepped. `isOpen`: where the panel is headed,
    /// for when the motion ends this frame. Returns true while frames are still needed with
    /// the spring at rest (the effect ringing out, or the pointer lens).
    func step(dt: CFTimeInterval, progress: CGFloat, geometry: NotchGeometry, isOpen: Bool) -> Bool {
        var moving = false
        if effects.isActive {
            moving = effects.step(dt: dt, velocity: driver.screenVelocity)
            if !moving, !driver.isSpringing, !driver.isHeld, !debugHoldsMotion {
                end(isOpen: isOpen)
            }
        }
        let pointerBusy = bender?.step(dt: dt, motion: motion(progress: progress, geometry: geometry)) ?? false
        return moving || pointerBusy
    }

    /// The panel just reached open or closed at `velocity`: a squash that rings out.
    func land(velocity: CGFloat) {
        guard effects.isActive else { return }
        effects.land(velocity: velocity)
    }

    /// Typing, clicking, dragging or scrolling reached the panel (the selected tab).
    func contentReceived(_ type: NSEvent.EventType) {
        guard content.isChanged(by: type) else { return }
        contentDidChange(content)
    }

    /// `source` may look different now (output, typing, a click, drag or scroll, a page load,
    /// a resize): its cached snapshot is stale. Only the selected tab's is retaken.
    func contentDidChange(_ source: MotionContent) {
        source.invalidateSnapshot()
        guard source === content else { return }
        lastContentChange = CACurrentMediaTime()
        scheduleIdleSnapshot()
    }

    /// Renders the motion layer once (zero effect: it looks exactly like the closed notch) so
    /// its shaders are compiled before the first real open, and has the window server build
    /// the Liquid Glass behind the notch.
    func warmUp() {
        guard !effects.isActive, !driver.isAnimating else { return }
        bender?.warmUp()
        effects.begin(with: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.effects.isActive, !self.driver.isAnimating, !self.driver.isHeld else { return }
            self.effects.end()
        }
    }

    // MARK: Private

    /// Everything is at rest and every effect is exactly zero: the live content comes back
    /// in the same frame the motion layer goes (both are SwiftUI state in one update).
    private func end(isOpen: Bool) {
        effects.end()
        _ = bender?.step(dt: 0, motion: nil)  // Hides the warp/glass unless the pointer needs it.
        // E.g. taken while closed (no caret): retake it before the next close.
        if isOpen, content.didReappear() { contentDidChange(content) }
        scheduleIdleSnapshot()
    }

    /// An asynchronous picture (the web page's) arrived. Mid-motion the one on screen stays:
    /// replacing it would be main-thread work during the animation; `end` asks again.
    private func snapshotRefreshed() {
        guard !effects.isActive else { return }
        _ = content.motionSnapshot()
    }

    /// The silhouette as drawn this frame and how hard it's moving, for bending the screen
    /// around it: speed peaking mid-way (or the anticipation swell); out while it grows, in
    /// while it shrinks. Nil at rest.
    private func motion(progress: CGFloat, geometry: NotchGeometry) -> SilhouetteMotion? {
        guard effects.isActive else { return nil }
        let frame = effects.frame
        let tuning = effects.tuning
        let shape = frame.silhouette(in: geometry, at: progress).shape
        let p = min(max(progress, 0), 1)
        let swell = tuning.anticipation > 0 ? frame.bulge / tuning.anticipation : 0
        let strength = min(max(frame.energy * (0.4 + 0.6 * sin(.pi * p)), swell), 1)
        // Smooth sign: a slow overshoot doesn't flip the warp abruptly. Frozen debug poses
        // have no velocity: they show an opening.
        let direction = debugHoldsMotion || swell > frame.energy
            ? 1 : CGFloat(tanh(Double(driver.screenVelocity) / 0.4))
        return SilhouetteMotion(
            silhouette: CGRect(x: shape.centerX - shape.width / 2, y: 0,
                               width: shape.width, height: shape.height),
            radius: shape.drawnBottomRadius, strength: strength, direction: direction)
    }

    /// Takes the next snapshot once the content has been quiet for half a second and the
    /// panel is at rest, so opening and closing find one ready and do no work up front.
    private func scheduleIdleSnapshot() {
        guard isEnabled, !snapshotRefreshPending else { return }
        snapshotRefreshPending = true
        let quiet: CFTimeInterval = 0.5
        let wait = max(quiet - (CACurrentMediaTime() - lastContentChange), 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.snapshotRefreshPending = false
            if CACurrentMediaTime() - self.lastContentChange < quiet {
                self.scheduleIdleSnapshot()  // Still busy: look again later.
                return
            }
            // Mid-motion the snapshot on screen is in use; `end` asks again at rest.
            guard !self.driver.isAnimating, !self.driver.isHeld, !self.effects.isActive else { return }
            self.content.refreshSnapshot()
        }
    }

    #if DEBUG
    /// Puts the motion layer up (fresh snapshot) without moving, as at the start of a motion,
    /// and keeps it up until `debugEnd`.
    func debugBegin() {
        debugHoldsMotion = true
        content.invalidateSnapshot()
        begin()
    }

    func debugEnd(isOpen: Bool) {
        debugHoldsMotion = false
        end(isOpen: isOpen)
    }

    /// Freezes the effect at `effect`, with the screen bent around the silhouette it gives.
    func debugPose(_ effect: MotionEffects.Frame, progress: CGFloat, geometry: NotchGeometry) {
        effects.debugSet(effect)
        _ = bender?.step(dt: 1.0 / 120, motion: motion(progress: progress, geometry: geometry))
    }
    #endif
}
