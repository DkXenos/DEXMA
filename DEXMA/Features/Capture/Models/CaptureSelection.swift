import CoreGraphics

/// What a finished stroke selects, in the display's points (top-left origin): the box around
/// the stroke plus `padding`, inside the display, at least `minimumSize` each way. A press that
/// barely moved is a click, which picks the window under it instead. Pure.
nonisolated enum CaptureSelection {
    static let padding: CGFloat = 8
    static let minimumSize: CGFloat = 24
    /// A press that never travels further than this (pt) from where it started is a click.
    static let clickTravel: CGFloat = 4

    /// The box around `points`, padded, clamped to `bounds`, grown to the minimum size (moved
    /// back inside if that pushed it out). Nil without points.
    static func rect(around points: [CGPoint], in bounds: CGRect) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -padding, dy: -padding)
        return fit(box, in: bounds)
    }

    /// `box` clamped to `bounds`, then at least `minimumSize` each way (grown about its centre and
    /// shifted back inside), never bigger than `bounds`.
    static func fit(_ box: CGRect, in bounds: CGRect) -> CGRect {
        var rect = box.intersection(bounds)
        if rect.isNull { rect = CGRect(x: box.midX, y: box.midY, width: 0, height: 0) }
        let width = min(max(rect.width, minimumSize), bounds.width)
        let height = min(max(rect.height, minimumSize), bounds.height)
        rect = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return rect
    }

    /// The press never left a small circle around where it started.
    static func isClick(_ points: [CGPoint]) -> Bool {
        guard let first = points.first else { return true }
        return points.allSatisfy { hypot($0.x - first.x, $0.y - first.y) < clickTravel }
    }

    /// A click at `point`: the frontmost window under it (`frames` front to back), inside
    /// `bounds`; over no window (the desktop), the whole display.
    static func window(at point: CGPoint, frames: [CGRect], in bounds: CGRect) -> CGRect {
        for frame in frames where frame.contains(point) {
            let visible = frame.intersection(bounds)
            if !visible.isNull, visible.width >= 1, visible.height >= 1 { return fit(visible, in: bounds) }
        }
        return bounds
    }
}
