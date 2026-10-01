import SwiftUI

/// The look of every control in the band beside the notch (tab segments, context buttons).
struct BandButtonStyle: ButtonStyle {
    /// The control's liquid lens (hover, press).
    let lens: ControlLens
    let size: CGSize
    /// Corner radius of the hover fill and the glass (nil: a capsule).
    var cornerRadius: CGFloat? = 8

    func makeBody(configuration: Configuration) -> some View {
        BandControl(configuration: configuration, lens: lens, size: size, cornerRadius: cornerRadius)
    }
}
