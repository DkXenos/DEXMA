import CoreGraphics
import Foundation

/// One finger on the trackpad, normalized to 0…1, with y = 1 at the top (far) edge.
nonisolated struct TouchPoint: Equatable {
    var id: Int32
    var x: CGFloat
    var y: CGFloat
}

nonisolated struct GestureParameters: Equatable {
    /// Fingers must land within this top fraction of the trackpad to start opening.
    var edgeZone: CGFloat = 0.12
    /// Vertical travel (fraction of trackpad height) that equals a full open or close.
    var triggerDistance: CGFloat = 0.3
}

nonisolated enum GestureEvent: Equatable {
    case began
    /// Progress change since `began`: + is toward open (fingers moving down).
    case changed(delta: CGFloat)
    /// Fingers lifted. `velocity` is in progress units per second.
    case ended(delta: CGFloat, velocity: CGFloat)
    case cancelled
}

/// Pure two-finger swipe recognizer, fed one multitouch frame at a time. No framework types,
/// so it's unit-tested with synthetic frames.
///
/// - Closed panel: two fingers landing in the top edge zone, then moving down → open.
/// - Open panel (`canClose`): two fingers anywhere moving up → close.
/// Anything else (sideways, the wrong way, a third finger) is ignored until all fingers lift,
/// so ordinary scrolling is left alone. Pure logic, so it isn't tied to the main actor.
nonisolated struct GestureRecognizer {
    enum Mode: Equatable {
        case open
        case close
    }

    private enum Phase: Equatable {
        case idle
        case armed(Mode)
        case tracking(Mode)
        case ignoring
    }

    // Thresholds in normalized trackpad units (the trackpad is ~9 cm tall, so 0.01 ≈ 1 mm).
    private static let startTravel: CGFloat = 0.012
    private static let wrongWayTravel: CGFloat = 0.03
    private static let sidewaysTravel: CGFloat = 0.06

    private var phase = Phase.idle
    private var startX: CGFloat = 0
    private var startY: CGFloat = 0
    private var lastDelta: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var velocity: CGFloat = 0

    /// True while scroll events should be swallowed: the fingers started in the open-gesture
    /// zone, or a swipe is being tracked.
    var isCapturing: Bool {
        switch phase {
        case .armed(.open), .tracking: true
        default: false
        }
    }

    var isTracking: Bool {
        if case .tracking = phase { return true }
        return false
    }

    mutating func reset() {
        phase = .idle
    }

    mutating func update(touches: [TouchPoint], time: TimeInterval, panelOpen: Bool,
                         canClose: Bool, parameters: GestureParameters) -> GestureEvent? {
        let count = touches.count
        let x = count > 0 ? touches.map(\.x).reduce(0, +) / CGFloat(count) : 0
        let y = count > 0 ? touches.map(\.y).reduce(0, +) / CGFloat(count) : 0

        switch phase {
        case .idle:
            guard count >= 2 else { return nil }
            startX = x
            startY = y
            let inEdgeZone = touches.allSatisfy { $0.y >= 1 - parameters.edgeZone }
            if count == 2, !panelOpen, inEdgeZone {
                phase = .armed(.open)
            } else if count == 2, panelOpen, canClose {
                phase = .armed(.close)
            } else {
                phase = .ignoring
            }
            return nil

        case .armed(let mode):
            guard count == 2 else {
                phase = count == 0 ? .idle : .ignoring
                return nil
            }
            let down = startY - y  // + when the fingers move toward the user
            let sideways = abs(x - startX)
            let along = mode == .open ? down : -down
            if sideways > Self.sidewaysTravel, sideways > abs(down) {
                phase = .ignoring
            } else if along < -Self.wrongWayTravel {
                phase = .ignoring
            } else if along > Self.startTravel {
                phase = .tracking(mode)
                lastDelta = 0
                lastTime = time
                velocity = 0
                return .began
            }
            return nil

        case .tracking:
            if count > 2 {
                phase = .ignoring
                return .cancelled
            }
            guard count == 2 else {
                // Lifting: one finger usually leaves a frame before the other.
                phase = count == 0 ? .idle : .ignoring
                return .ended(delta: lastDelta, velocity: velocity)
            }
            // 1:1 — travelling `triggerDistance` of the trackpad moves progress by 1.
            let delta = (startY - y) / parameters.triggerDistance
            let dt = time - lastTime
            if dt > 0 {
                // Exponential smoothing: frames arrive every ~8–11 ms and raw differences
                // are noisy; ~40 ms of memory keeps the release velocity honest.
                let instant = (delta - lastDelta) / CGFloat(dt)
                velocity = velocity * 0.6 + instant * 0.4
            }
            lastDelta = delta
            lastTime = time
            return .changed(delta: delta)

        case .ignoring:
            if count == 0 { phase = .idle }
            return nil
        }
    }
}
