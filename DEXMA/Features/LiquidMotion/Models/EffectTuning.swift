import CoreGraphics

/// Every constant of the liquid open/close effect. `full` is the designed look; the Settings
/// "Effect intensity" slider scales it with `scaled(by:)`. Velocities are in progress units
/// per second (progress 0 → 1 is closed → open); lengths are in points.
nonisolated struct EffectTuning: Equatable {
    // MARK: Squash & stretch
    /// A secondary "jelly" spring follows `stretchPerVelocity × |velocity|`, so the shape
    /// stretches along the motion while moving and wobbles when the motion stops.
    var stretchPerVelocity: CGFloat = 0.016
    /// Limit for stretch (+) and squash (−), as a fraction of the shape's size. The shaders'
    /// `maxSampleOffset` is sized for this.
    var maxStretch: CGFloat = 0.07
    var jellyFrequency: CGFloat = 5.5  // Hz
    var jellyDamping: CGFloat = 0.3  // Damping ratio; below 1 overshoots, i.e. wobbles.
    /// Landing kick: peak squash per unit of velocity when the panel reaches open or closed.
    var wobble: CGFloat = 0.012
    /// Anticipation: the notch swells by this fraction just as it starts to open.
    var anticipation: CGFloat = 0.07
    var anticipationDuration: Double = 0.16

    // MARK: Lens rim
    /// How far in from the edge the lens bends the content.
    var rimWidth: CGFloat = 30
    /// Displacement at the very edge at full speed (content is pulled in from deeper inside).
    var refraction: CGFloat = 7
    /// RGB split at the edge at full speed. Keep ≤ 1.5: felt more than seen.
    var aberration: CGFloat = 1.5

    // MARK: Screen warp (Screen Recording; see ScreenBender)
    /// How far the real screen is pushed out (opening) or pulled in (closing) right at the
    /// silhouette's edge, at full speed mid-way.
    var screenWarp: CGFloat = 14
    /// How far from the edge the screen still bends.
    var screenWarpReach: CGFloat = 46
    /// Colour warp: red bends this much further than green, blue this much less.
    var screenChroma: CGFloat = 0.25
    /// Pointer lens near the notch: magnification at its centre (0.22 ≈ 1.3×)…
    var hoverLens: CGFloat = 0.22
    var hoverLensRadius: CGFloat = 70
    /// …starting this far from the notch, full strength over it. Small on purpose: anything
    /// that comes near starts screen capture (and macOS's recording indicator), and the menu
    /// bar beside the notch is busy.
    var hoverReach: CGFloat = 28
    /// The screen right around the notch pushed out this much while the pointer is over it.
    var hoverPush: CGFloat = 3

    /// Fallback without Screen Recording (macOS 26): how far past the silhouette the Liquid
    /// Glass ring bends the screen at full speed. Kept narrow: wide, fast-changing glass
    /// smears into blur. 0 turns it off.
    var backdropRing: CGFloat = 10

    // MARK: Light
    /// Peak opacity of the specular line that sweeps down the rim as the panel opens.
    var highlight: CGFloat = 0.6
    /// Width of the sweeping band, as a fraction of the rim from the top edge to the bottom middle.
    var highlightWidth: CGFloat = 0.22
    /// Opacity of the faint glow just inside the rim.
    var glow: CGFloat = 0.08

    /// Speed at which lens, aberration and light reach full strength. A default open peaks
    /// around 3–4; a fast flick goes well past it.
    var referenceVelocity: CGFloat = 3

    static let full = EffectTuning()

    /// Everything visual scaled by `intensity` (0 = no effect at all, 1 = `full`).
    func scaled(by intensity: CGFloat) -> EffectTuning {
        let k = min(max(intensity, 0), 1)
        var t = self
        t.stretchPerVelocity *= k
        t.maxStretch *= k
        t.wobble *= k
        t.anticipation *= k
        t.refraction *= k
        t.backdropRing *= k
        t.screenWarp *= k
        t.hoverLens *= k
        t.hoverPush *= k
        t.aberration *= k
        t.highlight *= k
        t.glow *= k
        return t
    }

    /// False when scaled to nothing: the motion layer and its shaders are skipped entirely.
    var isVisible: Bool {
        maxStretch > 0 || refraction > 0 || aberration > 0 || highlight > 0 || glow > 0
            || backdropRing > 0 || screenWarp > 0 || hoverLens > 0
    }
}
