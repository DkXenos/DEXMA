import SwiftUI

/// The look of every control in the band beside the notch (tab segments, Search buttons).
struct BandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BandControl(configuration: configuration)
    }
}
