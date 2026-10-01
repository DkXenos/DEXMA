import CoreGraphics
import Foundation
import Testing
@testable import DEXMA

@MainActor
struct BandMotionTests {
    private func makeBand(reduceMotion: Bool = false, intensity: CGFloat = 1) -> BandMotion {
        let band = BandMotion()
        band.reduceMotion = { reduceMotion }
        band.tuning = EffectTuning.full.scaled(by: intensity)
        return band
    }

    /// Steps at 120 Hz until nothing moves (or `seconds` pass); returns how long it took.
    @discardableResult
    private func run(_ band: BandMotion, seconds: Double, each: (Double) -> Void = { _ in }) -> Double {
        var t = 0.0
        while t < seconds {
            let busy = band.step(dt: 1.0 / 120)
            t += 1.0 / 120
            each(t)
            if !busy { break }
        }
        return t
    }

    @Test func hoverBreathesThenRestsUnderThePointerThenDecaysToExactlyZero() {
        let band = makeBand()
        let lens = band.lens(for: "tab.search")
        lens.hover(at: CGPoint(x: 20, y: 12))
        #expect(lens.isActive)
        var peak: CGFloat = 0
        let settle = run(band, seconds: 2) { _ in peak = max(peak, lens.frame.strength) }
        #expect(peak > 0.9)  // The breath swells to (nearly) full…
        #expect(abs(lens.frame.strength - EffectTuning.full.controlRest) < 0.001)  // …then a gentle rest.
        #expect(lens.frame.presence == 1 && lens.isActive)  // Still attached while hovered.
        #expect(settle < 0.6)  // And no frames once resting.
        #expect(!band.step(dt: 1.0 / 120))

        lens.hover(at: nil)
        run(band, seconds: 2)
        #expect(!lens.isActive)
        #expect(lens.frame == ControlLens.Frame())
    }

    @Test func lensGlidesAfterThePointer() {
        let band = makeBand()
        let lens = band.lens(for: "tab.terminal")
        lens.hover(at: CGPoint(x: 10, y: 12))
        run(band, seconds: 1)
        lens.hover(at: CGPoint(x: 70, y: 12))
        _ = band.step(dt: 1.0 / 120)
        let first = lens.frame.center.x
        #expect(first > 10 && first < 40)  // Smoothed, not a jump…
        run(band, seconds: 1)
        #expect(lens.frame.center == CGPoint(x: 70, y: 12))  // …and it arrives exactly.
    }

    @Test func pressSquashesThenSpringsBackPastRest() {
        let band = makeBand()
        let lens = band.lens(for: "search.back")
        lens.setPressed(true)
        for _ in 0..<40 { _ = band.step(dt: 1.0 / 120) }
        let squash = lens.frame.pressScale(band.tuning)
        #expect(squash.height < 0.93 && squash.width > 1)
        lens.setPressed(false)
        var rebound: CGFloat = 0
        run(band, seconds: 2) { _ in rebound = min(rebound, lens.frame.press) }
        #expect(rebound < -0.05)  // Past rest on release…
        #expect(!lens.isActive && lens.frame.pressScale(band.tuning) == CGSize(width: 1, height: 1))
    }

    @Test func indicatorStretchesLikeADropletAndRestsAtExactlyOneByOne() {
        let band = makeBand()
        band.select(1)
        var maxStretch: CGFloat = 0
        var minStretch: CGFloat = 0
        run(band, seconds: 3) { _ in
            maxStretch = max(maxStretch, band.indicator.stretch)
            minStretch = min(minStretch, band.indicator.stretch)
        }
        #expect(maxStretch > 0.05)  // Longer while it slides…
        #expect(minStretch < -0.004)  // …squashed as it lands…
        #expect(band.indicator == BandMotion.Indicator(position: 1, stretch: 0))  // …then exact.
        #expect(band.indicator.scale == CGSize(width: 1, height: 1))
    }

    @Test func reduceMotionJumpsAndOffKeepsOnlyThePlainControl() {
        let calm = makeBand(reduceMotion: true)
        calm.select(1)
        #expect(calm.indicator == BandMotion.Indicator(position: 1, stretch: 0))
        #expect(!calm.step(dt: 1.0 / 120))
        let lens = calm.lens(for: "tab.search")
        lens.hover(at: CGPoint(x: 5, y: 5))
        lens.setPressed(true)
        #expect(!lens.isActive)

        let off = makeBand(intensity: 0)
        let offLens = off.lens(for: "tab.search")
        offLens.hover(at: CGPoint(x: 5, y: 5))
        #expect(!offLens.isActive)
        off.select(1)  // Still slides (no Reduce Motion), but never stretches.
        var stretched = false
        run(off, seconds: 3) { _ in stretched = stretched || off.indicator.stretch != 0 }
        #expect(!stretched && off.indicator.position == 1)
    }
}
