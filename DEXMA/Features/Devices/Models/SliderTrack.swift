import CoreGraphics

/// A Control Center-style level slider's geometry: a capsule whose white fill starts as a
/// circle at the left (where the icon sits) and grows to the full width at 1. Pure.
nonisolated struct SliderTrack: Equatable {
    let width: CGFloat
    let height: CGFloat

    /// The fill's width for `value` (0…1): never narrower than the icon's circle.
    func fillWidth(for value: Double) -> CGFloat {
        let v = CGFloat(min(max(value, 0), 1))
        return height + max(width - height, 0) * v
    }

    /// The value under the pointer at `x`: the fill's edge follows the pointer, centred on
    /// the circle's middle at 0.
    func value(at x: CGFloat) -> Double {
        let travel = width - height
        guard travel > 0 else { return 0 }
        return Double(min(max((x - height / 2) / travel, 0), 1))
    }
}
