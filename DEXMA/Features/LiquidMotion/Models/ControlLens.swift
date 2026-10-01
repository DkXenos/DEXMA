import CoreGraphics
import Foundation
import Observation

/// The liquid lens on one band control (a tab segment or a Search button) while the pointer is
/// over it or it's pressed. Stepped every display frame by `BandMotion`; every value is exactly
/// zero once it settles after the pointer leaves, and then `isActive` goes false and the control
/// drops its shader (LiquidEffects.metal's `liquidControlLens`).
@Observable
final class ControlLens {
    struct Frame: Equatable {
        /// 0 … 1: the magnifier that follows the pointer, there as long as the pointer is.
        var presence: CGFloat = 0
        /// 0 … 1 (the breath's peak): scales the bulge, rim refraction, aberration and light.
        var strength: CGFloat = 0
        /// Lens centre: the pointer, smoothed, in the control's coordinates (pt).
        var center: CGPoint = .zero
        /// Press, 0 … 1 at full squash; springs a little past 0 on release.
        var press: CGFloat = 0

        /// The press squash as a scale about the control's centre: shorter and a touch wider.
        func pressScale(_ tuning: EffectTuning) -> CGSize {
            let squash = tuning.pressSquash * press
            return CGSize(width: 1 + 0.4 * squash, height: 1 - squash)
        }
    }

    private(set) var frame = Frame()
    /// The shader is attached: hovered, pressed, or still settling.
    private(set) var isActive = false

    @ObservationIgnored var tuning = EffectTuning.full
    /// False with Reduce Motion or the intensity at Off: only the plain hover fill then.
    @ObservationIgnored var isEnabled: () -> Bool = { true }
    /// Gets display frames coming (the panel's link).
    @ObservationIgnored var wake: (() -> Void)?

    @ObservationIgnored private var pointer: CGPoint?
    @ObservationIgnored private var breathTime: Double?
    @ObservationIgnored private var pressed = false
    @ObservationIgnored private var pressSpring = JellySpring()

    /// The pointer moved over the control (`nil`: it left).
    func hover(at point: CGPoint?) {
        guard let point else {
            guard pointer != nil else { return }
            pointer = nil
            wake?()
            return
        }
        guard isEnabled() else { return }
        if pointer == nil {
            if !isActive || frame.presence == 0 { frame.center = point }
            breathTime = 0  // Entering: a breath.
        }
        pointer = point
        isActive = true
        wake?()
    }

    func setPressed(_ down: Bool) {
        guard down != pressed else { return }
        pressed = down
        guard isEnabled() || !down else { return }
        isActive = true
        wake?()
    }

    /// The panel is closing: let go, as if the pointer had left and the button was released.
    func release() {
        pressed = false
        hover(at: nil)
    }

    /// Advances one display frame. Returns false once nothing moves (resting under the pointer,
    /// or settled at exactly zero, which also detaches the shader).
    func step(dt: Double) -> Bool {
        guard isActive else { return false }
        let t = tuning
        var next = frame

        // Presence eases in and out quickly; the breath is one smooth swell on entry.
        let presenceTarget: CGFloat = pointer == nil ? 0 : 1
        next.presence += (presenceTarget - next.presence) * CGFloat(1 - exp(-dt / 0.06))
        if abs(next.presence - presenceTarget) < 0.002 { next.presence = presenceTarget }
        var pulse: CGFloat = 0
        if let elapsed = breathTime {
            let now = elapsed + dt
            if now >= t.controlBreathDuration {
                breathTime = nil
            } else {
                breathTime = now
                pulse = CGFloat(sin(.pi * now / t.controlBreathDuration))
            }
        }
        next.strength = next.presence * (t.controlRest + (1 - t.controlRest) * pulse)

        // The lens glides after the pointer, like a loupe over glass.
        if let pointer {
            let k = CGFloat(1 - exp(-dt / max(t.controlFollow, 0.001)))
            next.center.x += (pointer.x - next.center.x) * k
            next.center.y += (pointer.y - next.center.y) * k
            if abs(pointer.x - next.center.x) < 0.02, abs(pointer.y - next.center.y) < 0.02 {
                next.center = pointer
            }
        }

        // Pressed in, then springing back past rest on release (Camera Control).
        pressSpring.step(dt: dt, target: pressed && isEnabled() ? 1 : 0, frequency: t.pressFrequency,
                         damping: t.pressDamping, limit: 1.5)
        next.press = pressSpring.value

        // Held down, the press spring keeps frames coming until the button is released.
        let settled = next.presence == presenceTarget && breathTime == nil && pressSpring.isAtRest
            && !pressed && (pointer == nil || next.center == pointer)
        if settled, pointer == nil {
            frame = Frame()
            isActive = false
            return false
        }
        if next != frame { frame = next }
        return !settled
    }
}
