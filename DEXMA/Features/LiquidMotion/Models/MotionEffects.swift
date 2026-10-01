import Foundation
import Observation

/// State of the liquid effect while the panel moves, stepped once per display frame by the
/// panel's `SpringDriver`. Every value is exactly zero once the motion has settled; only
/// then does the live content come back (see `LiquidMotionEngine`).
@Observable
final class MotionEffects {
    struct Frame: Equatable {
        /// + taller and narrower (along the motion), − wider and shorter.
        var stretch: CGFloat = 0
        /// Uniform swelling just before opening (anticipation).
        var bulge: CGFloat = 0
        /// 0…1 from the speed on screen: scales lens, aberration and light.
        var energy: CGFloat = 0

        /// How much wider and taller the silhouette is, about its top-centre anchor (the notch
        /// hangs from the screen edge). Stretch is roughly volume-preserving (taller, narrower);
        /// the bulge swells both ways, more downward since the notch is so short. Exactly 1 × 1
        /// at rest. Never grows the silhouette past `limit` (the most the panel window can
        /// show, see `NotchGeometry.silhouetteLimit`), so a fast open is never cut off by the
        /// window's edge.
        func scale(width: CGFloat, height: CGFloat,
                   limit: CGSize = CGSize(width: CGFloat.infinity, height: .infinity)) -> CGSize {
            guard stretch != 0 || bulge != 0 else { return CGSize(width: 1, height: 1) }
            let sx = min((1 + bulge) * (1 - 0.5 * stretch), max(1, limit.width / max(width, 1)))
            let sy = min((1 + 1.6 * bulge) * (1 + stretch), max(1, limit.height / max(height, 1)))
            return CGSize(width: sx, height: sy)
        }
    }

    private(set) var frame = Frame()
    /// The motion layer (snapshot + shaders) is on screen instead of the live content.
    private(set) var isActive = false
    private(set) var snapshot: ContentSnapshot?
    /// The launch warm-up (see `LiquidMotionEngine.warmUp`): the layer also renders the band
    /// controls' shader once, so the first hover doesn't compile it.
    private(set) var isWarmUp = false

    @ObservationIgnored var tuning = EffectTuning.full
    @ObservationIgnored private var jelly = JellySpring()
    @ObservationIgnored private var anticipationTime: Double?

    func begin(with snapshot: ContentSnapshot?) {
        if let snapshot, snapshot != self.snapshot { self.snapshot = snapshot }
        isActive = true
    }

    /// Up with no picture, only to render the shaders once at launch.
    func beginWarmUp() {
        isWarmUp = true
        begin(with: nil)
    }

    /// Another tab's content took over mid-motion: show its picture instead (even none).
    func show(_ snapshot: ContentSnapshot?) {
        if snapshot != self.snapshot { self.snapshot = snapshot }
    }

    /// Back to the live content. Only called once everything is at rest.
    func end() {
        frame = Frame()
        jelly.reset()
        anticipationTime = nil
        isActive = false
        isWarmUp = false
    }

    /// The notch is about to open from closed: swell for a moment first.
    func anticipate() {
        guard tuning.anticipation > 0 else { return }
        anticipationTime = 0
    }

    /// The panel just reached open or closed at `velocity`: a squash that rings out.
    func land(velocity: CGFloat) {
        let omega = 2 * .pi * tuning.jellyFrequency
        jelly.velocity -= tuning.wobble * abs(velocity) * omega
    }

    /// Advances one display frame. `velocity` is the panel's speed on screen (progress/s).
    /// Returns false once everything is at exactly zero.
    func step(dt: Double, velocity: CGFloat) -> Bool {
        var next = frame
        let t = tuning
        let limit = t.maxStretch

        // Jelly: an underdamped spring chasing a stretch proportional to the speed.
        let target = min(t.stretchPerVelocity * abs(velocity), limit)
        jelly.step(dt: dt, target: target, frequency: t.jellyFrequency, damping: t.jellyDamping, limit: limit)
        next.stretch = jelly.value

        // Energy: quick to rise, a little slower to fall; snaps to zero once the motion stops.
        let targetEnergy = min(abs(velocity) / t.referenceVelocity, 1)
        let tau = targetEnergy > next.energy ? 0.025 : 0.07
        next.energy += (targetEnergy - next.energy) * CGFloat(1 - exp(-dt / tau))
        if targetEnergy == 0, next.energy < 0.004 { next.energy = 0 }

        // Anticipation: one smooth swell, over within `anticipationDuration`.
        if let elapsed = anticipationTime {
            let now = elapsed + dt
            if now >= t.anticipationDuration {
                anticipationTime = nil
                next.bulge = 0
            } else {
                anticipationTime = now
                next.bulge = t.anticipation * CGFloat(sin(.pi * now / t.anticipationDuration))
            }
        }

        if next != frame { frame = next }
        return next != Frame() || jelly.velocity != 0 || anticipationTime != nil
    }

    #if DEBUG
    func debugSet(_ value: Frame) {
        frame = value
    }
    #endif
}
