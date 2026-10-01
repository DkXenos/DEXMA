import SwiftUI

/// The panel while it moves: a snapshot of the content (terminal or web page) in place of the
/// live view, and a copy of the chrome (band, card stroke, page dots), both stretched with the
/// silhouette and bent by the lens shader (LiquidEffects.metal), plus the light on the rim. It
/// sits over the black silhouette, which stays an ordinary vector shape throughout (squashed
/// and stretched through its own size).
///
/// Only on screen while `effects.isActive`: at rest its shaders are off and it's hidden (a layer
/// opacity, so the live content and the live chrome take over in exactly the same frame; the
/// one transitional frame SwiftUI draws as the shaders switch is never seen).
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
    /// The chrome's copy for the motion (the live one is outside, see `NotchContentView`).
    @ViewBuilder let chrome: Chrome

    var body: some View {
        let active = effects.isActive
        ZStack(alignment: .topLeading) {
            // SwiftUI skips a layer effect whose content is all transparent (before the text
            // fades in), and the light must still be drawn. Black at this alpha over the black
            // silhouette changes no pixel.
            Color.black.opacity(0.004)
            if let snapshot = effects.snapshot {
                Image(decorative: snapshot.image, scale: snapshot.scale)
                    .frame(width: snapshot.size.width, height: snapshot.size.height)
                    .offset(x: snapshot.origin.x, y: snapshot.origin.y)
                    // The card's corners, as the live pages are clipped (ContentPagerView).
                    .frame(width: contentFrame.width, height: contentFrame.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: NotchGeometry.cardRadius, style: .continuous))
                    .offset(x: contentFrame.minX, y: contentFrame.minY)
                    .opacity(contentOpacity)
            }
            chrome
                .opacity(contentOpacity)
            if effects.isWarmUp {
                // The band controls' shader, rendered once at launch (identity: all zero) on
                // the closed notch's black, where this alpha changes no pixel.
                Color.black.opacity(0.004)
                    .frame(width: 16, height: 16)
                    .layerEffect(ControlLensEffect.shader(.zero), maxSampleOffset: ControlLensEffect.reach)
                    .offset(x: shape.centerX - 8, y: 4)
            }
        }
        .modifier(liquid(enabled: active))
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The stretch and the lens for this frame (all zero at rest), clipped to the silhouette.
    private func liquid(enabled: Bool) -> LiquidEffect {
        let energy = effects.frame.energy
        let tuning = effects.tuning
        let p = min(max(progress, 0), 1)
        // Lens and light peak mid-way and scale with speed; all zero at rest (energy = 0).
        let midway = sin(.pi * p)
        return LiquidEffect(
            panelSize: panelSize, shape: shape, scale: scale,
            fx: SIMD4(tuning.refraction * energy * (0.35 + 0.65 * midway), tuning.aberration * energy,
                      tuning.highlight * energy * (0.3 + 0.7 * midway),
                      tuning.glow * energy * midway),
            light: SIMD4(p, tuning.highlightWidth, tuning.rimWidth, 0),
            reach: Self.lensReach(tuning), enabled: enabled)
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
    static var stretchReach: CGSize { CGSize(width: NotchGeometry.margin, height: NotchGeometry.margin) }
}

/// LiquidEffects.metal's stretch and lens on a panel-sized layer, clipped to the silhouette.
private struct LiquidEffect: ViewModifier {
    let panelSize: CGSize
    let shape: NotchShape
    let scale: CGSize
    let fx: SIMD4<Double>
    let light: SIMD4<Double>
    let reach: CGSize
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
            .distortionEffect(
                ShaderLibrary.liquidStretch(.float4(shape.centerX, scale.width, scale.height, 0)),
                maxSampleOffset: CGSize(width: NotchGeometry.margin, height: NotchGeometry.margin),
                isEnabled: enabled)
            .layerEffect(
                ShaderLibrary.liquidLens(
                    .float4(shape.centerX, shape.width, shape.height, shape.drawnBottomRadius),
                    .float4(fx.x, fx.y, fx.z, fx.w),
                    .float4(light.x, light.y, light.z, light.w)),
                maxSampleOffset: reach, isEnabled: enabled)
            // Like the live content's mask: nothing shows outside the silhouette.
            .clipShape(shape)
    }
}
