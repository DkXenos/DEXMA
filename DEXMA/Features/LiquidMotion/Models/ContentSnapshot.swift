import CoreGraphics

/// A picture of the panel's content (the terminal or the Search card) at the content frame's
/// size, which the motion layer bends while the panel moves. Transparent where the content is,
/// so the black silhouette shows through as it does behind the live view.
struct ContentSnapshot: Equatable {
    let image: CGImage
    /// Pixels per point.
    let scale: CGFloat
    /// Where the picture's top-left corner sits in the card (pt): e.g. the terminal's padding.
    var origin: CGPoint = .zero

    /// The picture's size in points.
    var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    static func == (a: ContentSnapshot, b: ContentSnapshot) -> Bool {
        a.image === b.image
    }
}
