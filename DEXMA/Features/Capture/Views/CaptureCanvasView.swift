import AppKit

/// Hosts the overlay's layers with a top-left origin, like the overlay view and the points it
/// records. AppKit sets a hosted layer's geometry flip from its view's `isFlipped` (setting
/// `isGeometryFlipped` on the layer directly is overridden), so the view itself is flipped.
final class CaptureCanvasView: NSView {
    override var isFlipped: Bool { true }
}
