import CoreGraphics

/// The silhouette in one frame and how hard it's moving: what `ScreenBender` bends the screen
/// around.
struct SilhouetteMotion {
    var silhouette: CGRect  // Panel coordinates, top-left origin.
    var radius: CGFloat
    /// 0…1.
    var strength: CGFloat
    /// +1 growing (pushes the screen out), −1 shrinking (pulls it in).
    var direction: CGFloat
}
