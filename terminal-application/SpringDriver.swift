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
    private var target: CGFloat = 0
    private var spring = Spring()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    /// Called with the new value on every frame while the spring is moving.
    var onChange: ((CGFloat) -> Void)?

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
        self.target = target
        self.spring = spring
        if let initialVelocity { velocity = initialVelocity }
        lastTimestamp = nil
        displayLink?.isPaused = false
    }

    @objc private func step(_ link: CADisplayLink) {
        // Advance to when this frame will be shown. After a resume there's no previous
        // frame, so use one frame's duration; clamp so a hitch doesn't make the spring jump.
        let now = link.targetTimestamp
        let dt = min(now - (lastTimestamp ?? link.timestamp), 1.0 / 30)
        lastTimestamp = now

        spring.update(value: &value, velocity: &velocity, target: target, deltaTime: dt)
        // 0.0005 of the travel is under 0.25 pt: invisible, so snap and stop.
        if abs(value - target) < 0.0005, abs(velocity) < 0.01 {
            value = target
            velocity = 0
            link.isPaused = true
        }
        onChange?(value)
    }
}
