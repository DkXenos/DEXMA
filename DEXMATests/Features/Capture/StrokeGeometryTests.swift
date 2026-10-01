import CoreGraphics
import Testing
@testable import DEXMA

struct StrokeGeometryTests {
    @Test func curvePassesThroughEveryPoint() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: -5), CGPoint(x: 30, y: 0)]
        var ends: [CGPoint] = []
        StrokeGeometry.path(through: points).applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: ends.append(e.points[0])
            case .addCurveToPoint: ends.append(e.points[2])
            default: break
            }
        }
        #expect(ends == points)
    }

    @Test func chunksJoinWithTheSameTangents() {
        let points = (0..<10).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0 * $0)) }
        func controls(_ path: CGPath) -> [CGPoint] {
            var result: [CGPoint] = []
            path.applyWithBlock { element in
                if element.pointee.type == .addCurveToPoint {
                    result += [element.pointee.points[0], element.pointee.points[1], element.pointee.points[2]]
                }
            }
            return result
        }
        let whole = controls(StrokeGeometry.path(through: points))
        let split = controls(StrokeGeometry.path(through: points, segments: 0..<4))
            + controls(StrokeGeometry.path(through: points, segments: 4..<9))
        #expect(whole == split)
    }

    @Test func singlePointIsADot() {
        #expect(StrokeGeometry.path(through: [CGPoint(x: 5, y: 5)]).boundingBoxOfPath == CGRect(x: 5, y: 5, width: 0, height: 0))
    }

    @Test func resampleIsEvenAndKeepsTheEnds() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 100, y: 0)]
        let points = StrokeGeometry.resample(line, count: 11)
        #expect(points.count == 11)
        #expect(points.first == CGPoint(x: 0, y: 0) && points.last == CGPoint(x: 100, y: 0))
        for (k, point) in points.enumerated() { #expect(abs(point.x - CGFloat(k) * 10) < 0.0001) }
    }

    @Test func roundedRectPointsStartNearTheStrokeAndClose() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let points = StrokeGeometry.roundedRectPoints(rect, radius: 12, count: 200, startingNear: CGPoint(x: 210, y: 50),
                                                      clockwise: true)
        #expect(points.count == 200)
        #expect(abs(points[0].x - 200) < 1 && abs(points[0].y - 50) < 1)  // The right edge's middle.
        #expect(abs(points[199].x - points[0].x) < 0.001 && abs(points[199].y - points[0].y) < 0.001)
        // Clockwise on screen (y down) from the right edge goes down.
        #expect(points[1].y > points[0].y)
        // Every point is on the outline: inside the rect, on an edge or a corner arc.
        for point in points {
            #expect(point.x > -0.001 && point.x < 200.001 && point.y > -0.001 && point.y < 100.001)
        }
        let back = StrokeGeometry.roundedRectPoints(rect, radius: 12, count: 200, startingNear: CGPoint(x: 210, y: 50),
                                                    clockwise: false)
        #expect(back[1].y < back[0].y)
    }

    @Test func outlinePointsAreEvenlySpaced() {
        let rect = CGRect(x: 10, y: 10, width: 300, height: 200)
        let points = StrokeGeometry.roundedRectPoints(rect, radius: 12, count: 401, startingNear: .zero, clockwise: true)
        let step = StrokeGeometry.perimeter(rect, radius: 12) / 400
        for (a, b) in zip(points, points.dropFirst()) {
            #expect(hypot(b.x - a.x, b.y - a.y) <= step + 0.001)  // A chord is never longer than its arc.
            #expect(hypot(b.x - a.x, b.y - a.y) > step * 0.97)
        }
    }

    @Test func direction() {
        // On screen (y down): right, then down, then left is clockwise.
        #expect(StrokeGeometry.isClockwise([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]))
        #expect(!StrokeGeometry.isClockwise([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 0)]))
    }
}

struct CaptureLookTests {
    @Test func intensityScalesOnlyTheGlowAndShimmer() {
        let off = CaptureLook.full.scaled(by: 0)
        #expect(off.edgeGlow == 0 && off.shimmer == 0)
        #expect(off.dim == CaptureLook.full.dim && off.strokeWidth == CaptureLook.full.strokeWidth)
        #expect(CaptureLook.full.scaled(by: 1) == CaptureLook.full)
        #expect(abs(CaptureLook.full.scaled(by: 0.5).edgeGlow - CaptureLook.full.edgeGlow / 2) < 0.0001)
    }

    @Test func bandLayout() {
        #expect(CaptureBandLayout.width(chipAspect: nil) == 36)
        #expect(CaptureBandLayout.chipWidth(aspect: 1) == 20)
        #expect(CaptureBandLayout.chipWidth(aspect: 1.5) == 30)
        #expect(CaptureBandLayout.chipWidth(aspect: 4) == 36)
        #expect(CaptureBandLayout.chipWidth(aspect: 0.3) == 20)
        #expect(CaptureBandLayout.width(chipAspect: 1.5) == CGFloat(36 + 30 + 2 + 16 + 4))
    }
}
