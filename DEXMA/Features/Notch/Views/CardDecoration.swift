import SwiftUI

/// Depth for the black card: a 1 px inner stroke (white 7 %) around it and a very faint 1 px
/// highlight along the inside of its top edge (white 5 %, fading toward the corners), like
/// light catching the edge of glass.
struct CardDecoration: View {
    let size: CGSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let radius = NotchGeometry.cardRadius
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: pixel)
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                   .init(color: .white.opacity(0.05), location: 0.25),
                                   .init(color: .white.opacity(0.05), location: 0.75),
                                   .init(color: .white.opacity(0), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: max(size.width - 2 * radius, 0), height: pixel)
                .offset(x: radius, y: pixel)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
