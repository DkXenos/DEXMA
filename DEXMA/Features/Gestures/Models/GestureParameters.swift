import CoreGraphics

nonisolated struct GestureParameters: Equatable {
    /// Fingers must land within this top fraction of the trackpad to start opening.
    var edgeZone: CGFloat = 0.12
    /// Vertical travel (fraction of trackpad height) that equals a full open or close.
    var triggerDistance: CGFloat = 0.3
}
