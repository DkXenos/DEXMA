import CoreGraphics

/// Where a selection (the display's points, top-left origin) is in the frozen picture of that
/// display: its native pixels, rounded outward to whole pixels and kept inside the picture, so
/// the crop is never resampled. Pure.
nonisolated enum CaptureCrop {
    static func pixelRect(for selection: CGRect, displaySize: CGSize, imageSize: CGSize) -> CGRect {
        guard displaySize.width > 0, displaySize.height > 0 else { return .zero }
        let sx = imageSize.width / displaySize.width
        let sy = imageSize.height / displaySize.height
        // A hair of tolerance, so 100.0000001 doesn't round out to a whole extra pixel.
        let minX = (selection.minX * sx + 1e-6).rounded(.down)
        let minY = (selection.minY * sy + 1e-6).rounded(.down)
        let maxX = (selection.maxX * sx - 1e-6).rounded(.up)
        let maxY = (selection.maxY * sy - 1e-6).rounded(.up)
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let clipped = rect.intersection(CGRect(origin: .zero, size: imageSize))
        return clipped.isNull ? .zero : clipped
    }
}
