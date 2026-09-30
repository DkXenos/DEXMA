import SwiftUI

/// SwiftUI root of the panel. Phase 1: a black rect morphing between the notch and the
/// expanded size. Everything derives from `controller.progress`; nothing here animates.
struct NotchContentView: View {
    let controller: PanelController

    private static let closedCornerRadius: CGFloat = 8
    private static let openCornerRadius: CGFloat = 24

    var body: some View {
        let p = controller.progress
        let geometry = controller.geometry
        let notch = geometry.notchRect.size
        let expanded = NotchGeometry.expandedSize
        let width = max(0, lerp(notch.width, expanded.width, p))
        let height = max(0, lerp(notch.height, expanded.height, p))
        let radius = max(0, lerp(Self.closedCornerRadius, Self.openCornerRadius, p))

        // Square top corners: the shape stays flush with the top edge of the screen.
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
            .fill(.black)
            .frame(width: width, height: height)
            // No physical notch to hide under: fade in over the first 10% instead of
            // showing a black pill while closed.
            .opacity(geometry.hasNotch ? 1 : min(1, max(0, p * 10)))
            .position(x: geometry.notchCenterXInPanel, y: height / 2)
            .ignoresSafeArea()
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}
