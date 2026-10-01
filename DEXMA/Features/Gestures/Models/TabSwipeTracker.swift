import CoreGraphics
import Foundation

/// Turns a trackpad's phased scroll events into a two-finger tab swipe. Pure (no AppKit
/// types), so it's unit-tested with synthetic events.
///
/// Until the fingers have travelled `axisLockDistance` the events pass through untouched; then
/// the gesture locks to one axis until the fingers lift. Horizontal (|dx| > `horizontalRatio`
/// × |dy|) and allowed in that direction → a tab swipe: its events are swallowed and reported
/// as a page delta. Anything else → an ordinary scroll, passed through. Momentum events after
/// the fingers lift never move the tabs (and are swallowed after a tab swipe, so they don't
/// scroll the page underneath).
nonisolated struct TabSwipeTracker {
    enum Phase: Equatable {
        case none, mayBegin, began, changed, ended, cancelled
    }

    struct Input: Equatable {
        var phase: Phase
        var isMomentum: Bool
        /// The scroll deltas (pt): the direction content should move per the user's
        /// natural-scrolling setting.
        var dx: CGFloat
        var dy: CGFloat
        var time: TimeInterval
    }

    enum Output: Equatable {
        /// Leave the event alone.
        case pass
        /// Swallow it; nothing to report.
        case swallow
        /// A tab swipe started; `delta` pages so far (+ toward later tabs).
        case began(delta: CGFloat)
        case changed(delta: CGFloat)
        /// Fingers lifted (or the gesture was cancelled, at zero velocity), pages per second.
        case ended(delta: CGFloat, velocity: CGFloat)
    }

    private enum State: Equatable {
        case idle
        case deciding(dx: CGFloat, dy: CGFloat)
        case swiping
        case scrolling
    }

    private var state = State.idle
    private var delta: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastTime: TimeInterval = 0
    /// The last gesture was a tab swipe: its momentum events are swallowed.
    private var swallowsMomentum = false

    var isSwiping: Bool { state == .swiping }

    /// `allowed(direction)`: may a tab swipe go that way (+1 later tab, −1 earlier) here?
    mutating func handle(_ input: Input, tuning: GestureTuning, pageWidth: CGFloat,
                         allowed: (Int) -> Bool) -> Output {
        if input.isMomentum {
            return swallowsMomentum ? .swallow : .pass
        }
        let width = max(pageWidth, 1)
        switch input.phase {
        case .none, .mayBegin:
            return state == .swiping ? .swallow : .pass
        case .began:
            state = .deciding(dx: input.dx, dy: input.dy)
            swallowsMomentum = false
            delta = 0
            velocity = 0
            lastTime = input.time
            return decide(input, tuning: tuning, width: width, allowed: allowed)
        case .changed:
            switch state {
            case .deciding(let dx, let dy):
                state = .deciding(dx: dx + input.dx, dy: dy + input.dy)
                return decide(input, tuning: tuning, width: width, allowed: allowed)
            case .swiping:
                let step = -input.dx / width
                delta += step
                let dt = input.time - lastTime
                if dt > 0.0005 {
                    // ~40 ms of memory: raw per-event speeds are noisy.
                    velocity = velocity * 0.6 + step / CGFloat(dt) * 0.4
                    lastTime = input.time
                }
                return .changed(delta: delta)
            case .idle, .scrolling:
                return .pass
            }
        case .ended, .cancelled:
            defer { state = .idle }
            guard state == .swiping else { return .pass }
            swallowsMomentum = true
            // Fingers that stopped before lifting carry no speed.
            let still = input.time - lastTime > 0.08
            let release = input.phase == .cancelled || still ? 0 : velocity
            return .ended(delta: delta, velocity: release)
        }
    }

    private mutating func decide(_ input: Input, tuning: GestureTuning, width: CGFloat,
                                 allowed: (Int) -> Bool) -> Output {
        guard case .deciding(let dx, let dy) = state,
              (dx * dx + dy * dy).squareRoot() >= tuning.axisLockDistance else { return .pass }
        // Content moving left reveals the page on the right: a later tab.
        let direction = dx < 0 ? 1 : -1
        guard abs(dx) > tuning.horizontalRatio * abs(dy), allowed(direction) else {
            state = .scrolling
            return .pass
        }
        state = .swiping
        delta = -dx / width
        lastTime = input.time
        return .began(delta: delta)
    }
}
