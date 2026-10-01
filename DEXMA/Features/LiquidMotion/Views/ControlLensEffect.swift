import SwiftUI

/// The band controls' liquid glass (LiquidEffects.metal's `liquidControlLens`) on a control of
/// `size`, driven by its `ControlLens`: the control is padded by `margin` of transparent room
/// for the bulge and light (the shader's maxSampleOffset), then laid out at its own size again,
/// and squashed while pressed. At rest the shader is off (`isEnabled: false`: never run) and
/// the press scale is exactly 1 × 1, so the control draws exactly as before the hover.
struct ControlLensEffect: ViewModifier {
    /// Room around the control for the effect. Smaller than the gap to the notch (12 pt) and to
    /// the content card (6 pt below the band), so the warp never reaches either.
    static let margin: CGFloat = 4
    static let reach = CGSize(width: margin, height: margin)

    let lens: ControlLens
    let size: CGSize
    /// The control's corner radius (nil: a capsule).
    var cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        let frame = lens.frame
        let tuning = lens.tuning
        let press = frame.pressScale(tuning)
        let m = Self.margin
        let strength = frame.strength

        content
            .padding(m)
            // SwiftUI runs a layer effect only where the content draws something; the light and
            // the bulge need the whole control and its margin. Black at this alpha over the
            // black panel changes no pixel, and it's gone (alpha 0) at rest.
            .background(Color.black.opacity(lens.isActive ? 0.004 : 0))
            // One picture for the shader: otherwise SwiftUI may run it on the background, icon
            // and text separately and add the light once per item (boxes around each).
            .compositingGroup()
            // Attached for good, enabled only while active: the shader never runs at rest, and
            // the control always renders through the same offscreen layer. Adding or removing
            // the effect would switch the label between two anti-aliasings (a visible tick as
            // the lens leaves).
            .layerEffect(
                Self.shader(Uniforms(
                    control: SIMD4(m, m, size.width, size.height),
                    lens: SIMD4(frame.center.x + m, frame.center.y + m,
                                tuning.controlLensRadius * size.height, tuning.controlLens * frame.presence),
                    fx: SIMD4(tuning.controlRefraction * strength, tuning.controlAberration * strength,
                              tuning.controlHighlight * strength, tuning.controlBulge * strength),
                    cornerRadius: Double(cornerRadius ?? 0))),
                maxSampleOffset: Self.reach,
                isEnabled: lens.isActive)
            .padding(-m)
            .scaleEffect(x: press.width, y: press.height)
    }

    struct Uniforms {
        var control: SIMD4<Double>
        var lens: SIMD4<Double>
        var fx: SIMD4<Double>
        var cornerRadius: Double = 0

        static let zero = Uniforms(control: .zero, lens: .zero, fx: .zero)
    }

    static func shader(_ u: Uniforms) -> Shader {
        ShaderLibrary.liquidControlLens(
            .float4(u.control.x, u.control.y, u.control.z, u.control.w),
            .float4(u.lens.x, u.lens.y, u.lens.z, u.lens.w),
            .float4(u.fx.x, u.fx.y, u.fx.z, u.fx.w),
            .float4(margin, u.cornerRadius, 0, 0))
    }
}
