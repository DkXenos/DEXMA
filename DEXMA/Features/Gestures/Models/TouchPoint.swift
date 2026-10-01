import CoreGraphics

/// One finger on the trackpad, normalized to 0…1, with y = 1 at the top (far) edge.
nonisolated struct TouchPoint: Equatable {
    var id: Int32
    var x: CGFloat
    var y: CGFloat
}
