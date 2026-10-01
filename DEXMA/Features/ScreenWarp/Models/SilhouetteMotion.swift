import CoreGraphics

/// The silhouette in one frame, how hard it's moving and how far the screen stays pushed out
/// around it: what `ScreenBender` bends the screen around.
struct SilhouetteMotion {
    var silhouette: CGRect  // Panel coordinates, top-left origin.
    var radius: CGFloat
    /// 0…1.
    var strength: CGFloat
    /// +1 growing (pushes the screen out), −1 shrinking (pulls it in).
    var direction: CGFloat
    /// The push-out that stays while the notch is swollen or open (pt), on top of the motion's.
    var restingPush: CGFloat = 0
}
