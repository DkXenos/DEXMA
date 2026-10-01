import CoreGraphics

/// From `a` (t = 0) to `b` (t = 1). `t` isn't clamped: past 1 it keeps going (overshoot).
nonisolated func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// Eases from 0 (x ≤ 0) to 1 (x ≥ 1), flat at both ends.
nonisolated func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}
