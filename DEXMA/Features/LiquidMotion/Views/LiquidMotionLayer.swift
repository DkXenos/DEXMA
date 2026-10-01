import SwiftUI

/// The panel's SwiftUI chrome (band, card stroke, page dots) always, and while the panel
/// moves the content (terminal or web page) as a snapshot in place of the live view, all of it
/// stretched with the silhouette and bent by the lens shader (LiquidEffects.metal), plus the
/// light on the rim. It sits over the black silhouette, which stays an ordinary vector shape
/// throughout (squashed and stretched through its own size), so nothing but the content is
/// ever swapped; the chrome is the same views moving or not.
///
/// At rest both shaders are disabled (never run) and the snapshot is gone: the live content
/// shows under the chrome.
struct LiquidMotionLayer<Chrome: View>: View {
    let effects: MotionEffects
    /// The silhouette as drawn this frame, already scaled by `scale`.
    let shape: NotchShape
    /// Squash & stretch of the silhouette, applied to the content too.
    let scale: CGSize
    let progress: CGFloat
    let panelSize: CGSize
    let contentFrame: CGRect
    let contentOpacity: CGFloat
    /// Whether the chrome takes clicks (the panel is open).
    let chromeInteractive: Bool
    @ViewBuilder let chrome: Chrome

    var body: some View {
        let active = effects.isActive
        let energy = effects.frame.energy
        let tuning = effects.tuning
        let p = min(max(progress, 0), 1)
        // Lens and light peak mid-way and scale with speed; all zero at rest (energy = 0).
        let midway = sin(.pi * p)
        let radius = shape.drawnBottomRadius

        ZStack(alignment: .topLeading) {
            // SwiftUI skips a layer effect whose content is all transparent (before the text
            // fades in, or with no snapshot yet), and the light must still be drawn. Black at
            // this alpha over the black silhouette changes no pixel.
            Color.black.opacity(active ? 0.004 : 0)
                .allowsHitTesting(false)
            if active, let snapshot = effects.snapshot {
                Image(decorative: snapshot.image, scale: snapshot.scale)
                    .frame(width: snapshot.size.width, height: snapshot.size.height)
                    .offset(x: contentFrame.minX + snapshot.origin.x, y: contentFrame.minY + snapshot.origin.y)
                    .opacity(contentOpacity)
                    .allowsHitTesting(false)
            }
            chrome
                .opacity(contentOpacity)
                .allowsHitTesting(chromeInteractive)
            if effects.isWarmUp {
                // The band controls' shader, rendered once at launch (identity: all zero) on
                // the closed notch's black, where this alpha changes no pixel.
                Color.black.opacity(0.004)
                    .frame(width: 16, height: 16)
                    .layerEffect(ControlLensEffect.shader(.zero), maxSampleOffset: ControlLensEffect.reach)
                    .offset(x: shape.centerX - 8, y: 4)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .distortionEffect(
            ShaderLibrary.liquidStretch(.float4(shape.centerX, scale.width, scale.height, 0)),
            maxSampleOffset: Self.stretchReach,
            isEnabled: active)
        .layerEffect(
            ShaderLibrary.liquidLens(
                .float4(shape.centerX, shape.width, shape.height, radius),
                .float4(tuning.refraction * energy * (0.35 + 0.65 * midway),
                        tuning.aberration * energy,
                        tuning.highlight * energy * (0.3 + 0.7 * midway),
                        tuning.glow * energy * midway),
                .float4(p, tuning.highlightWidth, tuning.rimWidth, 0)),
            maxSampleOffset: Self.lensReach(tuning),
            isEnabled: active)
        // Like the live content's mask: nothing shows outside the silhouette.
        .clipShape(shape)
    }

    /// Compiles the shaders ahead of time (macOS 15+), the band controls' one too.
    /// `NotchViewModel.warmUpEffects` also renders the layer once at launch (with the controls'
    /// shader), which is what warms them on macOS 14.
    static func precompile() {
        guard #available(macOS 15, *) else { return }
        Task {
            try? await ShaderLibrary.liquidLens(.float4(0, 0, 0, 0), .float4(0, 0, 0, 0), .float4(0, 0, 0, 0))
                .compile(as: .layerEffect)
            try? await ShaderLibrary.liquidStretch(.float4(0, 1, 1, 0)).compile(as: .distortionEffect)
            try? await ControlLensEffect.shader(.zero).compile(as: .layerEffect)
        }
    }

    /// Furthest a lens sample lands from its pixel: the edge displacement plus the RGB split.
    private static func lensReach(_ tuning: EffectTuning) -> CGSize {
        let reach = (tuning.refraction + tuning.aberration).rounded(.up) + 1
        return CGSize(width: reach, height: reach)
    }

    /// The stretch moves content by at most the panel's transparent margin around the
    /// expanded shape (`MotionEffects.Frame.scale` clamps it to that).
    private static var stretchReach: CGSize { CGSize(width: NotchGeometry.margin, height: NotchGeometry.margin) }
}
