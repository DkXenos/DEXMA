import CoreGraphics

/// A picture of the panel's content (the terminal or the Search card) at the content frame's
/// size, which the motion layer bends while the panel moves. Transparent where the content is,
/// so the black silhouette shows through as it does behind the live view.
struct ContentSnapshot: Equatable {
    let image: CGImage
    /// Pixels per point.
    let scale: CGFloat

    static func == (a: ContentSnapshot, b: ContentSnapshot) -> Bool {
        a.image === b.image
    }
}
