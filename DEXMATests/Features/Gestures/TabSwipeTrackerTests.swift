import CoreGraphics
import Foundation
import Testing
@testable import DEXMA

/// Drives `TabSwipeTracker` with synthetic phased scroll events at ~120 Hz.
struct TabSwipeTrackerTests {
    private var tracker = TabSwipeTracker()
    private var time = 0.0
    private let tuning = GestureTuning.standard
    private let width: CGFloat = 600

    private mutating func send(_ phase: TabSwipeTracker.Phase, dx: CGFloat = 0, dy: CGFloat = 0,
                               momentum: Bool = false, allowed: Bool = true,
                               dt: Double = 1.0 / 120) -> TabSwipeTracker.Output {
        time += dt
        let input = TabSwipeTracker.Input(phase: phase, isMomentum: momentum, dx: dx, dy: dy, time: time)
        return tracker.handle(input, tuning: tuning, pageWidth: width) { _ in allowed }
    }

    /// A gesture of `steps` events moving (dx, dy) each; returns every output.
    private mutating func gesture(dx: CGFloat, dy: CGFloat, steps: Int = 30, allowed: Bool = true,
                                  lift: Bool = true) -> [TabSwipeTracker.Output] {
        var outputs = [send(.began, dx: dx, dy: dy, allowed: allowed)]
        for _ in 1..<steps { outputs.append(send(.changed, dx: dx, dy: dy, allowed: allowed)) }
        if lift { outputs.append(send(.ended, allowed: allowed)) }
        return outputs
    }

    @Test mutating func horizontalSwipeLocksAfterTheLockDistanceAndFollowsOneToOne() {
        // 4 pt per event to the left: content moves left, toward the next tab.
        let outputs = gesture(dx: -4, dy: 0.5)
        #expect(outputs[0] == .pass && outputs[1] == .began(delta: 8.0 / 600))  // 8 pt: locked.
        guard case .changed(let delta) = outputs[outputs.count - 2] else { Issue.record("no change"); return }
        #expect(abs(delta - 120.0 / 600) < 0.0001)  // 30 × 4 pt = a fifth of a page.
        guard case .ended(let end, let velocity) = outputs.last else { Issue.record("no end"); return }
        #expect(end == delta)
        #expect(velocity > 0.7 && velocity < 0.9)  // 4 pt / 8.3 ms ≈ 0.8 pages/s
    }

    @Test mutating func rightwardSwipeGoesToTheEarlierTab() {
        let outputs = gesture(dx: 5, dy: 0)
        guard case .ended(let delta, let velocity) = outputs.last else { Issue.record("no end"); return }
        #expect(delta < 0 && velocity < 0)
    }

    @Test mutating func verticalScrollPassesThroughUntouchedUntilTheFingersLift() {
        let outputs = gesture(dx: 1, dy: -6)
        #expect(outputs.allSatisfy { $0 == .pass })
        // Even if it turns sideways later: locked to vertical for this gesture.
        _ = send(.began, dx: 0, dy: -6)
        _ = send(.changed, dx: 0, dy: -6)
        #expect(send(.changed, dx: -20, dy: 0) == .pass)
    }

    @Test mutating func diagonalUnderTheRatioIsAScroll() {
        // |dx| = 1.4 |dy|: not horizontal enough.
        let outputs = gesture(dx: -4.2, dy: 3)
        #expect(outputs.allSatisfy { $0 == .pass })
    }

    @Test mutating func notAllowedThereScrollsInstead() {
        // E.g. over a web page that can still scroll sideways itself.
        let outputs = gesture(dx: -4, dy: 0, allowed: false)
        #expect(outputs.allSatisfy { $0 == .pass })
    }

    @Test mutating func momentumNeverMovesTabsAndIsSwallowedOnlyAfterASwipe() {
        _ = gesture(dx: -4, dy: 0)
        #expect(send(.none, dx: -10, momentum: true) == .swallow)
        _ = gesture(dx: 0, dy: -6)
        #expect(send(.none, dx: 0, dy: -10, momentum: true) == .pass)
    }

    @Test mutating func fingersThatStopBeforeLiftingCarryNoSpeed() {
        let outputs = gesture(dx: -4, dy: 0, lift: false)
        #expect(outputs.contains(.began(delta: 8.0 / 600)))
        guard case .ended(_, let velocity) = send(.ended, dt: 0.2) else { Issue.record("no end"); return }
        #expect(velocity == 0)
    }
}
