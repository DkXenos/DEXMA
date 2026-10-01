import CoreGraphics
import Foundation
import Testing
@testable import DEXMA

struct JellySpringTests {
    /// The loop `MotionEffects` ran before the jelly became its own type, verbatim.
    private struct Reference {
        var stretch: CGFloat = 0
        var jellyVelocity: CGFloat = 0

        mutating func step(dt: Double, target: CGFloat, t: EffectTuning) {
            let limit = t.maxStretch
            let omega = 2 * .pi * t.jellyFrequency
            let steps = max(1, Int((dt * 240).rounded(.up)))
            let h = CGFloat(dt) / CGFloat(steps)
            for _ in 0..<steps {
                let acceleration = omega * omega * (target - stretch) - 2 * t.jellyDamping * omega * jellyVelocity
                jellyVelocity += acceleration * h
                stretch = min(max(stretch + jellyVelocity * h, -limit), limit)
            }
            if target == 0, abs(stretch) < 0.0002, abs(jellyVelocity) < 0.002 {
                stretch = 0
                jellyVelocity = 0
            }
        }
    }

    @Test func matchesTheNotchsOriginalJellyExactly() {
        let t = EffectTuning.full
        var reference = Reference()
        var jelly = JellySpring()
        // Uneven frames (a hitch included), a motion, a landing kick, then rest.
        let dts = [1.0 / 120, 1.0 / 120, 1.0 / 60, 1.0 / 30, 1.0 / 120] + Array(repeating: 1.0 / 120, count: 300)
        for (i, dt) in dts.enumerated() {
            let speed: CGFloat = i < 40 ? 4 * sin(.pi * CGFloat(i) / 40) : 0
            if i == 40 {
                let kick = t.wobble * 1.5 * 2 * .pi * t.jellyFrequency
                reference.jellyVelocity -= kick
                jelly.velocity -= kick
            }
            let target = min(t.stretchPerVelocity * speed, t.maxStretch)
            reference.step(dt: dt, target: target, t: t)
            jelly.step(dt: dt, target: target, frequency: t.jellyFrequency, damping: t.jellyDamping, limit: t.maxStretch)
            #expect(jelly.value == reference.stretch && jelly.velocity == reference.jellyVelocity)
        }
        #expect(jelly.isAtRest)
    }
}
