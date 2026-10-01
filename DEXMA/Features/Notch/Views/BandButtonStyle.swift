import SwiftUI

/// The look of every control in the band beside the notch (tab segments, Search buttons).
struct BandButtonStyle: ButtonStyle {
    /// The control's liquid lens (hover, press).
    let lens: ControlLens
    let size: CGSize

    func makeBody(configuration: Configuration) -> some View {
        BandControl(configuration: configuration, lens: lens, size: size)
    }
}
