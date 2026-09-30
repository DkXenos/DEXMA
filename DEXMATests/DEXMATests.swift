import CoreGraphics
import SwiftUI
import Testing
@testable import DEXMA

/// Drives `GestureRecognizer` with synthetic two-finger paths at ~120 Hz.
struct GestureRecognizerTests {
    private var recognizer = GestureRecognizer()
    private var time: Double = 0
    private let parameters = GestureParameters(edgeZone: 0.12, triggerDistance: 0.3)

    /// Feeds frames with two fingers at mean (x, y) — plus `extra` more fingers — and returns
    /// every emitted event.
    private mutating func swipe(from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat),
                                frames: Int = 30, panelOpen: Bool = false, canClose: Bool = true,
                                extra: Int = 0) -> [GestureEvent] {
        var events: [GestureEvent] = []
        for i in 0...frames {
            let t = CGFloat(i) / CGFloat(frames)
            let x = start.0 + (end.0 - start.0) * t
            let y = start.1 + (end.1 - start.1) * t
            var touches = [TouchPoint(id: 1, x: x - 0.05, y: y), TouchPoint(id: 2, x: x + 0.05, y: y)]
            for n in 0..<extra { touches.append(TouchPoint(id: Int32(10 + n), x: 0.5, y: 0.5)) }
            time += 1.0 / 120
            if let event = recognizer.update(touches: touches, time: time, panelOpen: panelOpen,
                                             canClose: canClose, parameters: parameters) {
                events.append(event)
            }
        }
        return events
    }

    private mutating func lift(panelOpen: Bool = false) -> GestureEvent? {
        time += 1.0 / 120
        return recognizer.update(touches: [], time: time, panelOpen: panelOpen, canClose: true,
                                 parameters: parameters)
    }

    @Test mutating func downSwipeFromTopEdgeOpensOneToOne() {
        let events = swipe(from: (0.5, 0.95), to: (0.5, 0.65))
        #expect(events.first == .began)
        #expect(recognizer.isCapturing)
        guard case .changed(let delta) = events.last else { Issue.record("no change"); return }
        // 0.30 of travel with triggerDistance 0.3 → a full open.
        #expect(abs(delta - 1) < 0.01)
        guard case .ended(_, let velocity) = lift() else { Issue.record("no end"); return }
        #expect(velocity > 2)  // 1.0 progress in 0.25 s ≈ 4/s
        #expect(!recognizer.isCapturing)
    }

    @Test mutating func swipeStartingBelowEdgeZoneIsIgnored() {
        let events = swipe(from: (0.5, 0.7), to: (0.5, 0.3))
        #expect(events.isEmpty)
        #expect(!recognizer.isCapturing)
    }

    @Test mutating func upwardSwipeFromEdgeIsIgnoredAndReleasesCapture() {
        _ = swipe(from: (0.5, 0.95), to: (0.5, 0.95), frames: 2)
        #expect(recognizer.isCapturing)  // Armed: fingers resting in the edge zone.
        let events = swipe(from: (0.5, 0.95), to: (0.5, 1.0))
        #expect(events.isEmpty)
        #expect(!recognizer.isCapturing)
    }

    @Test mutating func sidewaysSwipeIsIgnored() {
        let events = swipe(from: (0.3, 0.95), to: (0.8, 0.94))
        #expect(events.isEmpty)
    }

    @Test mutating func threeFingersAreIgnored() {
        let events = swipe(from: (0.5, 0.95), to: (0.5, 0.6), extra: 1)
        #expect(events.isEmpty)
    }

    @Test mutating func thirdFingerMidSwipeCancels() {
        _ = swipe(from: (0.5, 0.95), to: (0.5, 0.8))
        let events = swipe(from: (0.5, 0.8), to: (0.5, 0.7), frames: 1, extra: 1)
        #expect(events.contains(.cancelled))
    }

    @Test mutating func upSwipeClosesWhenOpen() {
        let events = swipe(from: (0.5, 0.3), to: (0.5, 0.6), panelOpen: true)
        #expect(events.first == .began)
        guard case .changed(let delta) = events.last else { Issue.record("no change"); return }
        #expect(delta < -0.9)
        #expect(recognizer.isCapturing)
    }

    @Test mutating func upSwipeIgnoredWhenTerminalCanStillScroll() {
        let events = swipe(from: (0.5, 0.3), to: (0.5, 0.6), panelOpen: true, canClose: false)
        #expect(events.isEmpty)
        #expect(!recognizer.isCapturing)
    }

    @Test mutating func downSwipeWhileOpenIsIgnored() {
        // Scrolling back through history must keep working while the panel is open.
        let events = swipe(from: (0.5, 0.6), to: (0.5, 0.2), panelOpen: true)
        #expect(events.isEmpty)
    }
}

@MainActor
struct NotchGeometryTests {
    @Test func closedShapeMatchesNotchAndOpenShapeMatchesExpandedSize() {
        let notch = CGRect(x: 1000, y: 950, width: 185, height: 32)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 982),
                                     notchRect: notch, hasNotch: true,
                                     expandedSize: CGSize(width: 680, height: 400))
        let rect = CGRect(origin: .zero, size: geometry.panelFrame.size)
        let closed = geometry.shape(at: 0).path(in: rect).boundingRect
        #expect(abs(closed.width - 185) < 0.01 && abs(closed.height - 32) < 0.01)
        #expect(abs(geometry.panelFrame.minX + closed.minX - notch.minX) < 0.01)
        let open = geometry.shape(at: 1).path(in: rect).boundingRect
        #expect(abs(open.height - 400) < 0.01)
        #expect(abs(open.width - (680 + 2 * 12)) < 0.01)  // Body plus both ears.
        #expect(rect.contains(open))
    }

    @Test func pillOnScreensWithoutNotchIsRoundedAndCentered() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let pill = CGRect(x: 1280 - 75, y: 1440 - 24, width: 150, height: 24)
        let geometry = NotchGeometry(screenFrame: screen, notchRect: pill, hasNotch: false,
                                     expandedSize: CGSize(width: 680, height: 400))
        let shape = geometry.shape(at: 0)
        #expect(shape.bottomRadius == 12)  // Fully rounded ends.
        #expect(abs(geometry.panelFrame.midX - 1280) <= 0.5)
        #expect(geometry.panelFrame.maxY == 1440)
    }
}

struct DefaultsMigrationTests {
    @Test func copiesLegacyValuesOnceWithoutOverwriting() throws {
        let current = "dexma.tests.current.\(UUID().uuidString)"
        let legacy = "dexma.tests.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: current))
        defer {
            defaults.removePersistentDomain(forName: current)
            defaults.removePersistentDomain(forName: legacy)
        }
        defaults.setPersistentDomain(["panelWidth": 900.0, "bounce": 0.1], forName: legacy)
        defaults.set(0.3, forKey: "bounce")  // Already set under the new identifier: kept.

        let copied = DefaultsMigration.run(into: defaults, currentDomain: current, legacyDomain: legacy)
        #expect(copied == 1)
        #expect(defaults.double(forKey: "panelWidth") == 900)
        #expect(defaults.double(forKey: "bounce") == 0.3)

        defaults.setPersistentDomain(["panelWidth": 500.0], forName: legacy)
        #expect(DefaultsMigration.run(into: defaults, currentDomain: current, legacyDomain: legacy) == 0)
        #expect(defaults.double(forKey: "panelWidth") == 900)
    }

    @Test func doesNothingUnderTheLegacyIdentifier() {
        #expect(DefaultsMigration.run(currentDomain: DefaultsMigration.legacyDomain) == 0)
    }
}

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

    @Test func stretchStaysInsideThePanelMargin() {
        let frame = MotionEffects.Frame(stretch: 0.07, bulge: 0.07, energy: 1)
        for (width, height) in [(185.0, 32.0), (680.0, 400.0), (1100.0, 720.0)] {
            let scale = frame.scale(width: width, height: height)
            #expect(height * (scale.height - 1) <= NotchGeometry.margin)
            #expect(width * (scale.width - 1) / 2 <= NotchGeometry.margin)
        }
    }

    @Test func intensityOffMeansNoEffect() {
        #expect(!EffectTuning.full.scaled(by: 0).isVisible)
        #expect(EffectTuning.full.scaled(by: 1) == EffectTuning.full)
        #expect(EffectTuning.full.scaled(by: 0.5).aberration == 0.75)
    }
}
