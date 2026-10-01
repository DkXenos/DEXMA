import CoreGraphics

/// The "jelly" of the liquid model: an underdamped spring chasing a target (a stretch
/// proportional to speed), so a shape stretches along a motion and wobbles when it stops.
/// Used by the notch (`MotionEffects`) and the band's selection indicator (`BandMotion`).
nonisolated struct JellySpring: Equatable {
    private(set) var value: CGFloat = 0
    var velocity: CGFloat = 0

    var isAtRest: Bool { value == 0 && velocity == 0 }

    /// Advances `dt` seconds toward `target`, at `frequency` Hz with damping ratio `damping`,
    /// keeping the value within ±`limit`. Sub-stepped at 240 Hz so a long frame after a hitch
    /// stays stable; snaps to exactly zero once the target is zero and the motion is invisible.
    mutating func step(dt: Double, target: CGFloat, frequency: CGFloat, damping: CGFloat, limit: CGFloat) {
        let omega = 2 * .pi * frequency
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = CGFloat(dt) / CGFloat(steps)
        for _ in 0..<steps {
            let acceleration = omega * omega * (target - value) - 2 * damping * omega * velocity
            velocity += acceleration * h
            value = min(max(value + velocity * h, -limit), limit)
        }
        if target == 0, abs(value) < 0.0002, abs(velocity) < 0.002 {
            value = 0
            velocity = 0
        }
    }

    /// Stops dead (the motion it belonged to is over).
    mutating func reset() {
        value = 0
        velocity = 0
    }
}
