import AppKit
import Observation
import SwiftUI

/// The liquid model for the band beside the notch: the lens on each control (`ControlLens`)
/// and the tab selection indicator's droplet stretch — along its motion, by the same jelly
/// spring as the notch, squashed as it lands. The indicator's position is the panel's tab
/// progress (its own spring, see `NotchViewModel`); this only reads that spring's speed. Lenses
/// step on the panel's display link (`LiquidMotionEngine`), the stretch on the tab spring's;
/// both are exactly zero (and frame-free) at rest.
@Observable
final class BandMotion {
    struct Indicator: Equatable {
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
    @ObservationIgnored private var jelly = JellySpring()

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

    /// The panel is closing: every lens lets go.
    func releaseAll() {
        for lens in lenses.values { lens.release() }
    }

    /// One display frame of the panel's link (the lenses). True while any still moves.
    func step(dt: Double) -> Bool {
        var busy = false
        for lens in lenses.values where lens.isActive {
            if lens.step(dt: dt) { busy = true }
        }
        return busy
    }

    /// One frame of the tab spring, moving at `velocity` (tabs per second): the stretch chases
    /// a stretch proportional to the speed. True while it still moves.
    func stepIndicator(dt: Double, velocity: CGFloat) -> Bool {
        let t = tuning
        let target = reduceMotion() ? 0 : min(t.indicatorStretch * abs(velocity), t.indicatorMaxStretch)
        guard target != 0 || !jelly.isAtRest else { return false }
        jelly.step(dt: dt, target: target, frequency: t.jellyFrequency, damping: t.jellyDamping,
                   limit: t.indicatorMaxStretch)
        let next = Indicator(stretch: jelly.value)
        if next != indicator { indicator = next }
        return !jelly.isAtRest
    }

    /// The indicator reached its tab at `velocity` (tabs per second): a squash, kicked like the
    /// notch's landing (the same ratio of kick to stretch).
    func landIndicator(velocity: CGFloat) {
        let t = tuning
        guard t.stretchPerVelocity > 0, !reduceMotion() else { return }
        jelly.velocity -= t.wobble / t.stretchPerVelocity * t.indicatorStretch
            * abs(velocity) * 2 * .pi * t.jellyFrequency
    }
}
