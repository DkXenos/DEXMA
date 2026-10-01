import AppKit
import Observation
import SwiftUI

/// The liquid model for the band beside the notch: the lens on each control (`ControlLens`)
/// and the tab selection indicator, which slides like a droplet, stretched along its motion by
/// the same jelly spring as the notch and squashed as it lands. Stepped on the panel's display
/// link by `LiquidMotionEngine`; exactly zero (and frame-free) at rest.
@Observable
final class BandMotion {
    struct Indicator: Equatable {
        /// Where the indicator is, in segments (0 = first tab).
        var position: CGFloat = 0
        /// + longer along the motion and thinner, − shorter and taller (landing).
        var stretch: CGFloat = 0

        /// The stretch as a scale about the indicator's centre (exactly 1 × 1 at rest).
        var scale: CGSize {
            CGSize(width: 1 + stretch, height: 1 - 0.5 * stretch)
        }
    }

    private(set) var indicator = Indicator()

    @ObservationIgnored var tuning = EffectTuning.full {
        didSet { for lens in lenses.values { lens.tuning = tuning } }
    }
    @ObservationIgnored var reduceMotion: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// Gets display frames coming (the panel's link).
    @ObservationIgnored var wake: (() -> Void)?

    @ObservationIgnored private var lenses: [String: ControlLens] = [:]
    @ObservationIgnored private var target: CGFloat = 0
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var sliding = false
    @ObservationIgnored private var landed = true
    @ObservationIgnored private var jelly = JellySpring()
    /// Bouncy enough to land at speed and overshoot a hair, like a drop (and to give the
    /// landing kick something to work with).
    private let spring = Spring(duration: 0.4, bounce: 0.25)

    /// The liquid controls are on: not with Reduce Motion or the intensity at Off.
    var isEnabled: Bool {
        !reduceMotion() && tuning.controlsVisible
    }

    /// The lens of the control `id`, made on first use and kept.
    func lens(for id: String) -> ControlLens {
        if let lens = lenses[id] { return lens }
        let lens = ControlLens()
        lens.tuning = tuning
        lens.isEnabled = { [weak self] in self?.isEnabled ?? false }
        lens.wake = { [weak self] in self?.wake?() }
        lenses[id] = lens
        return lens
    }

    /// The selected tab is now the `index`th: the indicator slides there (jumps with Reduce
    /// Motion).
    func select(_ index: Int) {
        let newTarget = CGFloat(index)
        guard newTarget != target else { return }
        target = newTarget
        if reduceMotion() {
            indicator = Indicator(position: newTarget)
            velocity = 0
            sliding = false
            jelly.reset()
            return
        }
        sliding = true
        landed = false
        wake?()
    }

    /// The panel is closing: every lens lets go.
    func releaseAll() {
        for lens in lenses.values { lens.release() }
    }

    /// One display frame. Returns true while anything still moves.
    func step(dt: Double) -> Bool {
        var busy = false
        for lens in lenses.values where lens.isActive {
            if lens.step(dt: dt) { busy = true }
        }
        if sliding || !jelly.isAtRest {
            if stepIndicator(dt: dt) { busy = true }
        }
        return busy
    }

    private func stepIndicator(dt: Double) -> Bool {
        let t = tuning
        var next = indicator
        if sliding {
            let before = next.position - target
            spring.update(value: &next.position, velocity: &velocity, target: target, deltaTime: dt)
            if !landed, before * (next.position - target) <= 0 {
                landed = true
                // The landing squash, kicked like the notch's: the same ratio of kick to stretch.
                if t.stretchPerVelocity > 0 {
                    jelly.velocity -= t.wobble / t.stretchPerVelocity * t.indicatorStretch
                        * abs(velocity) * 2 * .pi * t.jellyFrequency
                }
            }
            // 0.0005 of a segment is well under a point: snap and stop.
            if abs(next.position - target) < 0.0005, abs(velocity) < 0.01 {
                next.position = target
                velocity = 0
                sliding = false
            }
        }
        let stretchTarget = sliding ? min(t.indicatorStretch * abs(velocity), t.indicatorMaxStretch) : 0
        jelly.step(dt: dt, target: stretchTarget, frequency: t.jellyFrequency, damping: t.jellyDamping,
                   limit: t.indicatorMaxStretch)
        next.stretch = jelly.value
        if next != indicator { indicator = next }
        return sliding || !jelly.isAtRest
    }
}
