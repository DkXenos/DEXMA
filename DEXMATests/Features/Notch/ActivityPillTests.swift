import CoreGraphics
import SwiftUI
import Testing
@testable import DEXMA

@MainActor
struct ActivityPillTests {
    private let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 982),
                                         notchRect: CGRect(x: 1000, y: 950, width: 185, height: 32), hasNotch: true,
                                         expandedSize: CGSize(width: 680, height: 400))

    @Test func pillIsNotchPlusWingsAndTwentyPointsTaller() {
        let notch = CGRect(x: 300, y: 0, width: 185, height: 32)
        let small = ActivityPillLayout(notch: notch, textWidth: 30, maxWidth: 1000)
        #expect(small.size == CGSize(width: 185 + 140, height: 52))  // 70 pt wings at least.
        #expect(small.iconCenter == CGPoint(x: 300 - 35, y: 26))
        #expect(small.textFrame.minX == 485 + 12 && small.textFrame.width == 70 - 24)
        let wide = ActivityPillLayout(notch: notch, textWidth: 150, maxWidth: 1000)
        #expect(wide.size.width == CGFloat(185 + 2 * (150 + 24)))
        let capped = ActivityPillLayout(notch: notch, textWidth: 900, maxWidth: 600)
        #expect(capped.size.width == 600)
    }

    private func same(_ a: NotchShape, _ b: NotchShape) -> Bool {
        a.width == b.width && a.height == b.height && a.bottomRadius == b.bottomRadius
            && a.earRadius == b.earRadius && a.centerX == b.centerX
    }

    @Test func pillBlendsIntoTheSilhouetteWithoutChangingItOtherwise() {
        let size = CGSize(width: 325, height: 52)
        #expect(same(geometry.shape(at: 0, activity: nil), geometry.shape(at: 0)))
        #expect(same(geometry.shape(at: 0.3, activity: NotchActivityShape(size: size, amount: 0)), geometry.shape(at: 0.3)))
        let out = geometry.shape(at: 0, activity: NotchActivityShape(size: size, amount: 1))
        #expect(out.width == 325 && out.height == 52 && out.bottomRadius == NotchGeometry.activityRadius)
        // Open, the panel is bigger than the pill everywhere: exactly the open shape.
        #expect(same(geometry.shape(at: 1, activity: NotchActivityShape(size: size, amount: 1)), geometry.shape(at: 1)))
        let rect = geometry.activityRect(size: size)
        #expect(rect.midX == geometry.notchRect.midX && rect.maxY == 982 && rect.height == 52)
    }
}
