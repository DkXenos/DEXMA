import CoreGraphics

/// One still picture of a display, taken as capture starts (DEXMA's windows left out): what the
/// user draws on, and what the selection is cropped from. Kept in memory only.
nonisolated struct FrozenScreen: Sendable {
    /// The display at its native pixels.
    let image: CGImage
    /// The display's size in points.
    let size: CGSize
    /// Every other app's window on that display, front to back, in the display's points (top-left
    /// origin): what a click picks.
    let windows: [CGRect]
}
