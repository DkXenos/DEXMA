import SwiftUI

/// One dot per tab below the card; the selected one is a capsule whose position and width
/// follow the tab progress, like iOS's page dots (`PageDotsLayout`).
struct PageDots: View {
    let count: Int
    let progress: CGFloat
    let center: CGPoint

    var body: some View {
        let layout = PageDotsLayout(count: count, progress: progress)
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.dots.enumerated()), id: \.offset) { _, dot in
                Capsule()
                    .fill(.white.opacity(dot.opacity))
                    .frame(width: dot.frame.width, height: dot.frame.height)
                    .offset(x: center.x + dot.frame.minX, y: center.y + dot.frame.minY)
            }
        }
        .allowsHitTesting(false)
    }
}
