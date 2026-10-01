import CoreGraphics
import Foundation
import Testing
@testable import DEXMA

@MainActor
struct MotionEffectsTests {
    /// Steps at 120 Hz with `velocity(t)` until everything rests; returns the frames seen.
    private func run(_ effects: MotionEffects, seconds: Double,
                     velocity: (Double) -> CGFloat) -> [MotionEffects.Frame] {
        var frames: [MotionEffects.Frame] = []
        var t = 0.0
        while t < seconds {
            let moving = effects.step(dt: 1.0 / 120, velocity: velocity(t))
            frames.append(effects.frame)
            t += 1.0 / 120
            if !moving, t > 0.05 { break }
        }
        return frames
    }

    @Test func settlesToExactlyZeroAfterMotion() {
        let effects = MotionEffects()
        // A spring-like open: speed up, slow down, stop.
        let frames = run(effects, seconds: 3) { t in t < 0.45 ? 4 * sin(.pi * t / 0.45) : 0 }
        #expect(frames.contains { $0.stretch > 0.02 && $0.energy > 0.5 })
        #expect(effects.frame == MotionEffects.Frame())
        #expect(!effects.step(dt: 1.0 / 120, velocity: 0))
        #expect(effects.frame.scale(width: 680, height: 400) == CGSize(width: 1, height: 1))
    }

    @Test func landingWobblesThenStops() {
        let effects = MotionEffects()
        effects.land(velocity: 1.5)
        let frames = run(effects, seconds: 3) { _ in 0 }
        let squash = frames.map(\.stretch).min() ?? 0
        #expect(squash < -0.01)  // Wider and shorter first…
        #expect(frames.contains { $0.stretch > 0 })  // …then rings past zero…
        #expect(effects.frame == MotionEffects.Frame())  // …and comes to rest exactly.
        #expect(Double(frames.count) / 120 < 1)
    }

    @Test func anticipationSwellsAndReturnsToZero() {
        let effects = MotionEffects()
        effects.anticipate()
        let frames = run(effects, seconds: 1) { _ in 0 }
        #expect((frames.map(\.bulge).max() ?? 0) > 0.05)
        #expect(effects.frame.bulge == 0)
        let peak = MotionEffects.Frame(stretch: 0, bulge: 0.07, energy: 0)
        let scale = peak.scale(width: 185, height: 32)
        #expect(scale.width > 1 && scale.height > scale.width)
    }

    @Test func stretchNeverLeavesThePanelWindow() {
        let frame = MotionEffects.Frame(stretch: 0.07, bulge: 0.07, energy: 1)
        for expanded in [CGSize(width: 680, height: 400), CGSize(width: 1100, height: 720)] {
            let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 3000, height: 2000),
                                         notchRect: CGRect(x: 1400, y: 1968, width: 185, height: 32),
                                         hasNotch: true, expandedSize: expanded)
            let limit = geometry.silhouetteLimit()
            // Fully open plus spring overshoot: the worst case for a fast open.
            for progress in [0.0, 0.5, 1.0, 1.06, 1.25] as [CGFloat] {
                let shape = frame.silhouette(in: geometry, at: progress).shape
                #expect(shape.height <= geometry.panelFrame.height - 1 + 0.001)
                #expect(shape.width <= limit.width + 0.001)
            }
        }
    }

    @Test func silhouetteAtRestIsTheShapeItself() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 3000, height: 2000),
                                     notchRect: CGRect(x: 1400, y: 1968, width: 185, height: 32),
                                     hasNotch: true, expandedSize: CGSize(width: 680, height: 400))
        for progress in [0.0, 0.3, 1.0] as [CGFloat] {
            let silhouette = MotionEffects.Frame().silhouette(in: geometry, at: progress)
            let shape = geometry.shape(at: progress)
            #expect(silhouette.scale == CGSize(width: 1, height: 1))
            #expect(silhouette.shape.width == shape.width && silhouette.shape.height == shape.height)
        }
    }

    @Test func intensityOffMeansNoEffect() {
        #expect(!EffectTuning.full.scaled(by: 0).isVisible)
        #expect(EffectTuning.full.scaled(by: 1) == EffectTuning.full)
        #expect(EffectTuning.full.scaled(by: 0.5).aberration == 0.75)
    }
}
