import CoreGraphics

/// Every constant of capture mode's look and motion. `full` is the designed look; the Settings
/// "Capture effects" slider (which follows the glass strength unless set apart) scales the edge
/// glow and the stroke's shimmer with `scaled(by:)`. Lengths in points, times in seconds.
nonisolated struct CaptureLook: Equatable {
    /// The frozen screen darkens this much while drawing, and outside the selection after it.
    var dim: CGFloat = 0.18
    var selectedDim: CGFloat = 0.42
    /// The stroke: white, round caps; its soft glow is wider strokes of fading white beneath.
    var strokeWidth: CGFloat = 4
    var glowWidths: [CGFloat] = [10, 18, 30]
    var glowOpacities: [CGFloat] = [0.22, 0.09, 0.035]
    /// The outline the stroke becomes, around the selection.
    var outlineWidth: CGFloat = 3
    var selectionRadius: CGFloat = 12
    /// The selected area lifts toward you: its scale and shadow.
    var lift: CGFloat = 1.02
    var liftShadowRadius: CGFloat = 22
    var liftShadowOpacity: CGFloat = 0.55
    /// Colour running along the stroke's glow (opacity) and how long one pass takes.
    var shimmer: CGFloat = 0.75
    var shimmerPeriod: Double = 2.6
    /// The glow around the display's edges: opacity, how far in it reaches, one turn of its colours.
    var edgeGlow: CGFloat = 0.85
    var edgeGlowWidth: CGFloat = 26
    var edgeGlowPeriod: Double = 7

    var fadeIn: Double = 0.18
    var morph: Double = 0.3
    /// The lifted selection stays still this long before it flies.
    var hold: Double = 0.06
    var flight: Double = 0.42
    var fadeOut: Double = 0.2
    /// Reduce Motion: everything just fades, this fast.
    var reducedFade: Double = 0.15

    static let full = CaptureLook()

    /// The edge glow and the shimmer scaled by `intensity` (0 = none, 1 = `full`); the dim, the
    /// stroke and its glow stay (they show what's selected).
    func scaled(by intensity: CGFloat) -> CaptureLook {
        let k = min(max(intensity, 0), 1)
        var look = self
        look.edgeGlow *= k
        look.shimmer *= k
        return look
    }
}
