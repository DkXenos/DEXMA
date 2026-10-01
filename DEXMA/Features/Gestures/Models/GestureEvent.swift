import CoreGraphics

nonisolated enum GestureEvent: Equatable {
    case began
    /// Progress change since `began`: + is toward open (fingers moving down).
    case changed(delta: CGFloat)
    /// Fingers lifted. `velocity` is in progress units per second.
    case ended(delta: CGFloat, velocity: CGFloat)
    case cancelled
}
