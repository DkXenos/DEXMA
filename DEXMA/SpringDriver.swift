import AppKit
import QuartzCore
import SwiftUI

/// Steps a value toward a target with a SwiftUI `Spring`, once per display frame.
///
/// `value` is always what's on screen, so a new target (or, later, a gesture) can take
/// over mid-flight and the spring carries on with its current velocity.
final class SpringDriver: NSObject {
    private(set) var value: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    /// Speed of `value` on screen (per second): the spring's velocity, or while `set` holds the
    /// value (a finger dragging it), measured from successive `set` calls.
    private(set) var screenVelocity: CGFloat = 0
    /// The spring is moving toward its target.
    private(set) var isSpringing = false
    /// `set` put the value where it is; it stays there until the next `animate`.
    private(set) var isHeld = false
    /// Keep display frames coming while held, for `onFrame` (the motion effects).
    var runsWhileHeld = false

    private var target: CGFloat = 0
    private var spring = Spring()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var hasArrived = true
    private var heldVelocity: CGFloat = 0
    private var lastSetTime: CFTimeInterval?

    /// Called with the new value on every frame while the spring is moving.
    var onChange: ((CGFloat) -> Void)?
    /// Called once when the spring settles on its target.
    var onRest: ((CGFloat) -> Void)?
    /// Called once per `animate`, the first time the value reaches the target (before any
    /// overshoot rings out): the moment the panel "lands". Gets the target and the velocity.
    var onArrive: ((_ target: CGFloat, _ velocity: CGFloat) -> Void)?
    /// Extra work on every display frame, after the spring has stepped. Return true to keep
    /// frames coming once the spring is at rest.
    var onFrame: ((_ deltaTime: CFTimeInterval) -> Bool)?

    var isAnimating: Bool { displayLink.map { !$0.isPaused } ?? false }

    #if DEBUG
    /// Frame-pacing probe: (vsync timestamp, main-thread time spent in this step).
    var debugFrameLog: ((CFTimeInterval, CFTimeInterval) -> Void)?
    #endif

    /// The link follows `window` across displays. Created once, paused while at rest.
    init(window: NSWindow) {
        super.init()
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused = true
        // .common keeps it firing while a menu or other event-tracking loop runs.
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func animate(to target: CGFloat, with spring: Spring, initialVelocity: CGFloat? = nil) {
        // Too small a trip to call a landing (e.g. re-targeting where it already is).
        hasArrived = abs(target - value) < 0.02
        self.target = target
        self.spring = spring
        if let initialVelocity { velocity = initialVelocity }
        isSpringing = true
        isHeld = false
        lastTimestamp = nil
        displayLink?.isPaused = false
    }

    /// Starts frames (for `onFrame`) if the link is resting; the spring itself stays put.
    func wake() {
        guard displayLink?.isPaused == true else { return }
        lastTimestamp = nil
        displayLink?.isPaused = false
    }

    /// Jump straight to `value` (e.g. following a finger), stopping any animation.
    func set(_ value: CGFloat) {
        let now = CACurrentMediaTime()
        if isSpringing {
            heldVelocity = velocity  // Grabbed mid-flight: carry the speed it had.
        } else if let last = lastSetTime, isHeld, now - last > 0.001 {
            // Smoothed like the gesture recognizer's release velocity (~40 ms of memory).
            heldVelocity = heldVelocity * 0.6 + (value - self.value) / CGFloat(now - last) * 0.4
        } else {
            heldVelocity = 0
        }
        lastSetTime = now
        isSpringing = false
        isHeld = true
        if runsWhileHeld {
            if displayLink?.isPaused == true {
                lastTimestamp = nil
                displayLink?.isPaused = false
            }
        } else {
            displayLink?.isPaused = true
        }
        self.value = value
        velocity = 0
        onChange?(value)
    }

    @objc private func step(_ link: CADisplayLink) {
        #if DEBUG
        let stepStart = CACurrentMediaTime()
        defer { debugFrameLog?(link.timestamp, CACurrentMediaTime() - stepStart) }
        #endif
        // Advance to when this frame will be shown. After a resume there's no previous
        // frame, so use one frame's duration; clamp so a hitch doesn't make the spring jump.
        let now = link.targetTimestamp
        let dt = min(now - (lastTimestamp ?? link.timestamp), 1.0 / 30)
        lastTimestamp = now

        if isSpringing {
            let before = value - target
            spring.update(value: &value, velocity: &velocity, target: target, deltaTime: dt)
            if !hasArrived, before * (value - target) <= 0 || abs(value - target) < 0.004 {
                hasArrived = true
                onArrive?(target, velocity)
            }
            // 0.0005 of the travel is under 0.25 pt: invisible, so snap and stop.
            if abs(value - target) < 0.0005, abs(velocity) < 0.01 {
                value = target
                velocity = 0
                isSpringing = false
                screenVelocity = 0
                onChange?(value)
                onRest?(value)
            } else {
                screenVelocity = velocity
                onChange?(value)
            }
        } else if isHeld {
            // Fingers resting without moving: no new `set`, so the speed dies away.
            if let last = lastSetTime, CACurrentMediaTime() - last > 0.05 {
                heldVelocity *= 0.5
                if abs(heldVelocity) < 0.001 { heldVelocity = 0 }
            }
            screenVelocity = heldVelocity
        } else {
            screenVelocity = 0
        }

        let wantsFrames = onFrame?(dt) ?? false
        if !isSpringing, !wantsFrames {
            link.isPaused = true
        }
    }
}
