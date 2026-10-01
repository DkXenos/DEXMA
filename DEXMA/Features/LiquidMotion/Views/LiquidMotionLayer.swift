import SwiftUI

/// The content (terminal or Search card) while the panel moves: a snapshot of it, stretched
/// with the silhouette and bent by the lens shader (LiquidEffects.metal), plus the light on
/// the rim. It sits over the black silhouette, which stays an ordinary vector shape throughout
/// (squashed and stretched through its own size), so nothing but the content is ever swapped.
///
/// Only on screen while `effects.isActive`; at rest it's transparent with both shaders
/// disabled, and the live content shows instead.
struct LiquidMotionLayer: View {
    let effects: MotionEffects
    /// The silhouette as drawn this frame, already scaled by `scale`.
    let shape: NotchShape
    /// Squash & stretch of the silhouette, applied to the content too.
    let scale: CGSize
    let progress: CGFloat
    let panelSize: CGSize
    let contentFrame: CGRect
    let contentOpacity: CGFloat

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
            Color.black.opacity(0.004)
            if let snapshot = effects.snapshot {
                Image(decorative: snapshot.image, scale: snapshot.scale)
                    .frame(width: contentFrame.width, height: contentFrame.height)
                    .offset(x: contentFrame.minX, y: contentFrame.minY)
                    .opacity(contentOpacity)
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
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Compiles both shaders ahead of time (macOS 15+). `NotchViewModel.warmUpEffects` also
    /// renders the layer once at launch, which is what warms them on macOS 14.
    static func precompile() {
        guard #available(macOS 15, *) else { return }
        Task {
            try? await ShaderLibrary.liquidLens(.float4(0, 0, 0, 0), .float4(0, 0, 0, 0), .float4(0, 0, 0, 0))
                .compile(as: .layerEffect)
            try? await ShaderLibrary.liquidStretch(.float4(0, 1, 1, 0)).compile(as: .distortionEffect)
        }
    }

    /// Furthest a lens sample lands from its pixel: the edge displacement plus the RGB split.
    private static func lensReach(_ tuning: EffectTuning) -> CGSize {
        let reach = (tuning.refraction + tuning.aberration).rounded(.up) + 1
        return CGSize(width: reach, height: reach)
    }

    /// The stretch moves content by at most the panel's transparent margin around the
    /// expanded shape (`MotionEffects.Frame.scale` clamps it to that).
    private static let stretchReach = CGSize(width: NotchGeometry.margin, height: NotchGeometry.margin)
}
