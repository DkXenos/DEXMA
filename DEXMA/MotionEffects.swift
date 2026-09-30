import Foundation
import Observation

/// State of the liquid effect while the panel moves, stepped once per display frame by the
/// panel's `SpringDriver`. Every value is exactly zero once the motion has settled; only
/// then does the live terminal come back (see `PanelController`).
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
        /// at rest. Clamped so the silhouette stays inside the panel's transparent margin.
        func scale(width: CGFloat, height: CGFloat) -> CGSize {
            guard stretch != 0 || bulge != 0 else { return CGSize(width: 1, height: 1) }
            let room = 0.9 * NotchGeometry.margin
            let sx = min((1 + bulge) * (1 - 0.5 * stretch), 1 + 2 * room / max(width, 1))
            let sy = min((1 + 1.6 * bulge) * (1 + stretch), 1 + room / max(height, 1))
            return CGSize(width: sx, height: sy)
        }
    }

    private(set) var frame = Frame()
    /// The motion layer (snapshot + shaders) is on screen instead of the live terminal.
    private(set) var isActive = false
    private(set) var snapshot: TerminalSnapshot?

    @ObservationIgnored var tuning = EffectTuning.full
    @ObservationIgnored private var jellyVelocity: CGFloat = 0
    @ObservationIgnored private var anticipationTime: Double?

    func begin(with snapshot: TerminalSnapshot?) {
        if let snapshot, snapshot != self.snapshot { self.snapshot = snapshot }
        isActive = true
    }

    /// Back to the live terminal. Only called once everything is at rest.
    func end() {
        frame = Frame()
        jellyVelocity = 0
        anticipationTime = nil
        isActive = false
    }

    /// The notch is about to open from closed: swell for a moment first.
    func anticipate() {
        guard tuning.anticipation > 0 else { return }
        anticipationTime = 0
    }

    /// The panel just reached open or closed at `velocity`: a squash that rings out.
    func land(velocity: CGFloat) {
        let omega = 2 * .pi * tuning.jellyFrequency
        jellyVelocity -= tuning.wobble * abs(velocity) * omega
    }

    /// Advances one display frame. `velocity` is the panel's speed on screen (progress/s).
    /// Returns false once everything is at exactly zero.
    func step(dt: Double, velocity: CGFloat) -> Bool {
        var next = frame
        let t = tuning
        let limit = t.maxStretch

        // Jelly: an underdamped spring chasing a stretch proportional to the speed. Sub-stepped
        // so a long frame after a hitch stays stable.
        let target = min(t.stretchPerVelocity * abs(velocity), limit)
        let omega = 2 * .pi * t.jellyFrequency
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = CGFloat(dt) / CGFloat(steps)
        for _ in 0..<steps {
            let acceleration = omega * omega * (target - next.stretch) - 2 * t.jellyDamping * omega * jellyVelocity
            jellyVelocity += acceleration * h
            next.stretch = min(max(next.stretch + jellyVelocity * h, -limit), limit)
        }
        if target == 0, abs(next.stretch) < 0.0002, abs(jellyVelocity) < 0.002 {
            next.stretch = 0
            jellyVelocity = 0
        }

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
        return next != Frame() || jellyVelocity != 0 || anticipationTime != nil
    }

    #if DEBUG
    func debugSet(_ value: Frame) {
        frame = value
    }
    #endif
}
