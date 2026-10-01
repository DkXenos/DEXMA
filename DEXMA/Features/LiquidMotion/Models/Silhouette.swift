import CoreGraphics

/// The notch silhouette as drawn in one frame: the shape for the panel's progress, squashed
/// and stretched by the liquid effect, plus that squash and stretch (exactly 1 × 1 at rest),
/// which the content gets too.
struct Silhouette {
    let shape: NotchShape
    let scale: CGSize
}

extension MotionEffects.Frame {
    /// The silhouette at `progress` in `geometry` with this frame's squash and stretch, never
    /// grown past what the panel window can show.
    func silhouette(in geometry: NotchGeometry, at progress: CGFloat) -> Silhouette {
        let base = geometry.shape(at: progress)
        let scale = self.scale(width: base.width, height: base.height, limit: geometry.silhouetteLimit())
        return Silhouette(shape: base.scaled(by: scale), scale: scale)
    }
}
