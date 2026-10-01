import SwiftUI

/// One control in the band: its label, on a white 12 % capsule while the pointer is over it.
struct BandControl: View {
    static let hoverFill = Color.white.opacity(0.12)

    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
            .background(Capsule().fill(hovering && isEnabled ? Self.hoverFill : .clear))
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
    }
}
