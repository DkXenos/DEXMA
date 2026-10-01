import SwiftUI

/// One control in the band: its label, on a white 12 % fill while the pointer is over it. Under
/// the pointer the liquid lens (`ControlLensEffect`) bends both, its centre and light following
/// the pointer; pressing squashes it. Without the effect (Reduce Motion, intensity Off, or at
/// rest) it's exactly the plain control.
struct BandControl: View {
    static let hoverFill = Color.white.opacity(0.12)

    let configuration: ButtonStyleConfiguration
    let lens: ControlLens
    let size: CGSize
    let cornerRadius: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? size.height / 2, style: .continuous)
        ZStack {
            shape.fill(hovering && isEnabled ? Self.hoverFill : .clear)
            configuration.label
        }
        .frame(width: size.width, height: size.height)
        .opacity(isEnabled ? 1 : 0.35)
        .modifier(ControlLensEffect(lens: lens, size: size, cornerRadius: cornerRadius))
        .contentShape(shape)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hovering = true
                if isEnabled { lens.hover(at: point) }
            case .ended:
                hovering = false
                lens.hover(at: nil)
            }
        }
        .onChange(of: configuration.isPressed) { _, pressed in
            lens.setPressed(pressed && isEnabled)
        }
    }
}
