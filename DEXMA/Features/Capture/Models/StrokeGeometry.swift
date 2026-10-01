import CoreGraphics

/// The drawn stroke's shape: a smooth curve through every point the pointer passed (uniform
/// Catmull–Rom as cubic Béziers, so no corners between samples), and the point lists the
/// release animation morphs between (the stroke and the selection's rounded rectangle, the same
/// number of points each, so Core Animation can interpolate the two paths). Pure.
nonisolated enum StrokeGeometry {
    /// Points closer than this (pt) to the last kept one add nothing but jitter.
    static let minimumSpacing: CGFloat = 1.5

    /// The curve through `points` from segment `segments.lowerBound` (from that point to the next)
    /// up to, not including, `segments.upperBound`. Each segment's tangents come from its
    /// neighbours (clamped at the ends), so neighbouring ranges join without a kink. A single
    /// point is a dot (a zero-length line, which a round cap draws as a disc).
    static func path(through points: [CGPoint], segments: Range<Int>? = nil) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        guard points.count > 1 else {
            path.move(to: first)
            path.addLine(to: first)
            return path
        }
        let range = segments ?? 0..<(points.count - 1)
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= points.count - 1 else { return path }
        let last = points.count - 1
        path.move(to: points[range.lowerBound])
        for i in range {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, last)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// `count` points evenly spaced along the polyline through `points` (first and last kept).
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = points.first, count > 1 else { return points.isEmpty ? [] : [points[0]] }
        let total = length(points)
        guard total > 0 else { return Array(repeating: first, count: count) }
        var result = [first]
        result.reserveCapacity(count)
        var segment = 0
        var walked: CGFloat = 0  // Length up to the start of `segment`.
        for k in 1..<(count - 1) {
            let target = total * CGFloat(k) / CGFloat(count - 1)
            while segment < points.count - 2 {
                let piece = hypot(points[segment + 1].x - points[segment].x, points[segment + 1].y - points[segment].y)
                if walked + piece >= target { break }
                walked += piece
                segment += 1
            }
            let a = points[segment], b = points[segment + 1]
            let piece = hypot(b.x - a.x, b.y - a.y)
            let t = piece > 0 ? min(max((target - walked) / piece, 0), 1) : 0
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        result.append(points[points.count - 1])
        return result
    }

    /// Whether the stroke turns clockwise as seen on screen (y down): the sign of its area.
    static func isClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count > 2 else { return true }
        var area: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst() + [points[0]]) { area += a.x * b.y - b.x * a.y }
        return area >= 0
    }

    /// `count` points around the rounded rectangle (closed: the last is the first), evenly by
    /// length, starting at the point of the outline nearest `start` and going clockwise on
    /// screen or not. The stroke morphs onto these with as little travel as possible.
    static func roundedRectPoints(_ rect: CGRect, radius: CGFloat, count: Int, startingNear start: CGPoint,
                                  clockwise: Bool) -> [CGPoint] {
        guard count > 1 else { return [start] }
        let r = min(radius, rect.width / 2, rect.height / 2)
        let total = perimeter(rect, radius: r)
        guard total > 0 else { return Array(repeating: CGPoint(x: rect.midX, y: rect.midY), count: count) }
        // The outline's point nearest `start`: good enough at a few points' resolution.
        let probes = 720
        var startLength: CGFloat = 0
        var nearest = CGFloat.infinity
        for k in 0..<probes {
            let s = total * CGFloat(k) / CGFloat(probes)
            let p = point(on: rect, radius: r, at: s)
            let d = hypot(p.x - start.x, p.y - start.y)
            if d < nearest { nearest = d; startLength = s }
        }
        let direction: CGFloat = clockwise ? 1 : -1
        return (0..<count).map { k in
            let s = startLength + direction * total * CGFloat(k) / CGFloat(count - 1)
            return point(on: rect, radius: r, at: s)
        }
    }

    static func perimeter(_ rect: CGRect, radius r: CGFloat) -> CGFloat {
        2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
    }

    /// The point `s` along the outline (wrapping), measured clockwise on screen (y down) from the
    /// top edge's left end.
    static func point(on rect: CGRect, radius r: CGFloat, at s: CGFloat) -> CGPoint {
        let total = perimeter(rect, radius: r)
        var s = s.truncatingRemainder(dividingBy: total)
        if s < 0 { s += total }
        let w = rect.width - 2 * r, h = rect.height - 2 * r, arc = .pi / 2 * r
        // Top edge, top-right corner, right edge, bottom-right, bottom, bottom-left, left, top-left.
        let corners = [CGPoint(x: rect.maxX - r, y: rect.minY + r), CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                       CGPoint(x: rect.minX + r, y: rect.maxY - r), CGPoint(x: rect.minX + r, y: rect.minY + r)]
        let edges: [(CGPoint, CGPoint, CGFloat)] = [
            (CGPoint(x: rect.minX + r, y: rect.minY), CGPoint(x: 1, y: 0), w),
            (CGPoint(x: rect.maxX, y: rect.minY + r), CGPoint(x: 0, y: 1), h),
            (CGPoint(x: rect.maxX - r, y: rect.maxY), CGPoint(x: -1, y: 0), w),
            (CGPoint(x: rect.minX, y: rect.maxY - r), CGPoint(x: 0, y: -1), h),
        ]
        for side in 0..<4 {
            let (origin, step, length) = edges[side]
            if s <= length { return CGPoint(x: origin.x + step.x * s, y: origin.y + step.y * s) }
            s -= length
            if s <= arc || side == 3 {
                // Angles on screen (y down): −90° is up; each corner turns a quarter clockwise.
                let angle = -CGFloat.pi / 2 + CGFloat(side) * .pi / 2 + (r > 0 ? min(s, arc) / r : 0)
                return CGPoint(x: corners[side].x + r * cos(angle), y: corners[side].y + r * sin(angle))
            }
            s -= arc
        }
        return CGPoint(x: rect.minX + r, y: rect.minY)
    }
}
