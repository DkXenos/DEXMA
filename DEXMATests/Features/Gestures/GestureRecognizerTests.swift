import CoreGraphics
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
