import CoreGraphics
import Testing
@testable import DEXMA

struct CaptureSelectionTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func boxAroundTheStrokeWithPadding() {
        let points = [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 150), CGPoint(x: 250, y: 400)]
        #expect(CaptureSelection.rect(around: points, in: display) == CGRect(x: 92, y: 142, width: 216, height: 266))
    }

    @Test func clampedToTheDisplay() {
        let points = [CGPoint(x: 2, y: 3), CGPoint(x: 1510, y: 980)]
        #expect(CaptureSelection.rect(around: points, in: display) == display)
    }

    @Test func tinyStrokeGrowsToTheMinimumAboutItsCentre() {
        let rect = CaptureSelection.rect(around: [CGPoint(x: 500, y: 500), CGPoint(x: 502, y: 501)], in: display)
        #expect(rect == CGRect(x: 489, y: 488.5, width: 24, height: 24))
    }

    @Test func minimumSizeAtTheEdgeStaysOnTheDisplay() {
        let rect = CaptureSelection.rect(around: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], in: display)
        #expect(rect == CGRect(x: 0, y: 0, width: 24, height: 24))
        let corner = CaptureSelection.rect(around: [CGPoint(x: 1512, y: 982)], in: display)
        #expect(corner == CGRect(x: 1488, y: 958, width: 24, height: 24))
    }

    @Test func clickOrStroke() {
        #expect(CaptureSelection.isClick([CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 11)]))
        #expect(!CaptureSelection.isClick([CGPoint(x: 10, y: 10), CGPoint(x: 15, y: 10)]))
        #expect(CaptureSelection.isClick([]))
    }

    @Test func clickPicksTheFrontmostWindowElseTheDisplay() {
        let front = CGRect(x: 100, y: 100, width: 400, height: 300)
        let back = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(CaptureSelection.window(at: CGPoint(x: 150, y: 150), frames: [front, back], in: display) == front)
        #expect(CaptureSelection.window(at: CGPoint(x: 700, y: 500), frames: [front, back], in: display) == back)
        #expect(CaptureSelection.window(at: CGPoint(x: 1000, y: 900), frames: [front, back], in: display) == display)
        // A window hanging off the display: only its visible part.
        let off = CGRect(x: 1400, y: -50, width: 400, height: 300)
        #expect(CaptureSelection.window(at: CGPoint(x: 1450, y: 10), frames: [off], in: display)
                == CGRect(x: 1400, y: 0, width: 112, height: 250))
    }
}

struct CaptureCropTests {
    @Test func nativePixelsAtTwoX() {
        let rect = CaptureCrop.pixelRect(for: CGRect(x: 92, y: 142, width: 216, height: 266),
                                         displaySize: CGSize(width: 1512, height: 982),
                                         imageSize: CGSize(width: 3024, height: 1964))
        #expect(rect == CGRect(x: 184, y: 284, width: 432, height: 532))
    }

    @Test func fractionalPointsRoundOutwardAndStayInside() {
        let rect = CaptureCrop.pixelRect(for: CGRect(x: 489, y: 488.5, width: 24, height: 24),
                                         displaySize: CGSize(width: 1512, height: 982),
                                         imageSize: CGSize(width: 3024, height: 1964))
        #expect(rect == CGRect(x: 978, y: 977, width: 48, height: 48))
        let edge = CaptureCrop.pixelRect(for: CGRect(x: 1500, y: 970, width: 40, height: 40),
                                         displaySize: CGSize(width: 1512, height: 982),
                                         imageSize: CGSize(width: 3024, height: 1964))
        #expect(edge == CGRect(x: 3000, y: 1940, width: 24, height: 24))
    }
}
