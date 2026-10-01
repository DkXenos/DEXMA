import AppKit

/// The panel's content view: the screen warp and Liquid Glass below, the SwiftUI content
/// above. Flipped, so subviews use the same top-left coordinates as the SwiftUI layout.
final class PanelContentView: NSView {
    override var isFlipped: Bool { true }
}
