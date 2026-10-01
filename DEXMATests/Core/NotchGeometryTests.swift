import CoreGraphics
import SwiftUI
import Testing
@testable import DEXMA

@MainActor
struct NotchGeometryTests {
    @Test func closedShapeMatchesNotchAndOpenShapeMatchesExpandedSize() {
        let notch = CGRect(x: 1000, y: 950, width: 185, height: 32)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 982),
                                     notchRect: notch, hasNotch: true,
                                     expandedSize: CGSize(width: 680, height: 400))
        let rect = CGRect(origin: .zero, size: geometry.panelFrame.size)
        let closed = geometry.shape(at: 0).path(in: rect).boundingRect
        #expect(abs(closed.width - 185) < 0.01 && abs(closed.height - 32) < 0.01)
        #expect(abs(geometry.panelFrame.minX + closed.minX - notch.minX) < 0.01)
        let open = geometry.shape(at: 1).path(in: rect).boundingRect
        #expect(abs(open.height - 400) < 0.01)
        #expect(abs(open.width - (680 + 2 * 12)) < 0.01)  // Body plus both ears.
        #expect(rect.contains(open))
    }

    @Test func pillOnScreensWithoutNotchIsRoundedAndCentered() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let pill = CGRect(x: 1280 - 75, y: 1440 - 24, width: 150, height: 24)
        let geometry = NotchGeometry(screenFrame: screen, notchRect: pill, hasNotch: false,
                                     expandedSize: CGSize(width: 680, height: 400))
        let shape = geometry.shape(at: 0)
        #expect(shape.bottomRadius == 12)  // Fully rounded ends.
        #expect(abs(geometry.panelFrame.midX - 1280) <= 0.5)
        #expect(geometry.panelFrame.maxY == 1440)
    }

    @Test func hoverZoneCoversTheNotchAndGrowsWhilePeeking() {
        let notch = CGRect(x: 1000, y: 950, width: 185, height: 32)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 982),
                                     notchRect: notch, hasNotch: true,
                                     expandedSize: CGSize(width: 680, height: 400))
        let resting = geometry.hoverZone(peeking: false)
        let peeking = geometry.hoverZone(peeking: true)
        #expect(resting.contains(CGPoint(x: notch.midX, y: notch.midY)))
        #expect(resting.maxY > notch.maxY)  // Right up to the top edge of the screen.
        #expect(peeking.contains(resting))
        let beside = CGPoint(x: notch.minX - 10, y: notch.midY)
        #expect(!resting.contains(beside) && peeking.contains(beside))
    }

    @Test func bandSitsBesideTheNotchAndContentBelowIt() {
        let notch = CGRect(x: 1000, y: 950, width: 185, height: 32)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2000, height: 982),
                                     notchRect: notch, hasNotch: true,
                                     expandedSize: CGSize(width: 680, height: 400))
        let notchInPanel = notch.offsetBy(dx: -geometry.panelFrame.minX, dy: 0)
        let tabs = geometry.tabBandFrame
        let actions = geometry.actionBandFrame
        let content = geometry.contentFrame
        #expect(geometry.bandHeight == 32)
        // Never under the notch, and inside the body like the content card.
        #expect(tabs.maxX <= notchInPanel.minX - NotchGeometry.notchGap + 0.01)
        #expect(actions.minX >= notchInPanel.maxX + NotchGeometry.notchGap - 0.01)
        #expect(abs(tabs.minX - content.minX) < 0.01 && abs(actions.maxX - content.maxX) < 0.01)
        #expect(tabs.width > 200 && actions.width > 200)
        // The content card starts below the band, where the terminal always was.
        #expect(content.minY == 38)

        // A short pill still gets a band tall enough for the controls.
        let pill = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                 notchRect: CGRect(x: 1205, y: 1420, width: 150, height: 20),
                                 hasNotch: false, expandedSize: CGSize(width: 680, height: 400))
        #expect(pill.bandHeight == 28 && pill.contentFrame.minY == 34)
    }
}
