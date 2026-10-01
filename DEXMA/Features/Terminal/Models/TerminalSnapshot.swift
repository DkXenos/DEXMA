import AppKit
import SwiftTerm

/// A picture of the terminal that matches what's on screen pixel for pixel, for the motion
/// layer: SwiftUI shaders can't render the live AppKit view.
///
/// `cacheDisplay` gets the text (drawn in `draw(_:)`) but not the two subviews that live in
/// their own layers, so those are added by hand: the caret, drawn by its layer delegate, and
/// the overlay scroller's knob, a rounded layer with a background colour. The background is
/// left transparent: the live terminal is transparent too and shows the black shape through.
/// Checked against the window server's own composite with `-effecttest` (Debug).
struct TerminalSnapshot: Equatable {
    let image: CGImage
    let scale: CGFloat
    /// Whether the caret is in the picture: only when the terminal had focus, so a snapshot
    /// never shows a caret the live view wouldn't.
    let showsCaret: Bool

    static func == (a: TerminalSnapshot, b: TerminalSnapshot) -> Bool {
        a.image === b.image
    }

    static func capture(_ view: TerminalView) -> TerminalSnapshot? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / bounds.width
        let showsCaret = view.hasFocus
        if let graphics = NSGraphicsContext(bitmapImageRep: rep) {
            // Already in points (the rep's size), y-up like the unflipped terminal view.
            let context = graphics.cgContext
            for subview in view.subviews where !subview.isHidden {
                if let scroller = subview as? NSScroller {
                    drawKnob(of: scroller, in: context)
                } else if showsCaret, String(describing: type(of: subview)) == "CaretView" {
                    drawCaret(subview, in: context)
                }
            }
            context.flush()
        }
        guard let image = rep.cgImage else { return nil }
        return TerminalSnapshot(image: image, scale: scale, showsCaret: showsCaret)
    }

    /// Drawn fully opaque: the live caret's blink is restarted (at full opacity) when the
    /// live view comes back, so the two match at the swap.
    private static func drawCaret(_ caret: NSView, in context: CGContext) {
        guard let layer = caret.layer else { return }
        context.saveGState()
        context.translateBy(x: caret.frame.minX, y: caret.frame.minY)
        layer.delegate?.draw?(layer, in: context)
        context.restoreGState()
    }

    private static func drawKnob(of scroller: NSScroller, in context: CGContext) {
        guard let layer = scroller.layer else { return }
        for knob in layer.sublayers ?? [] where !knob.isHidden {
            let opacity = CGFloat(knob.presentation()?.opacity ?? knob.opacity)
            guard opacity > 0, let color = knob.backgroundColor else { continue }
            // AppKit gives the knob a NaN corner radius, meaning fully rounded ends.
            let half = min(knob.frame.width, knob.frame.height) / 2
            let radius = knob.cornerRadius.isNaN ? half : min(knob.cornerRadius, half)
            var frame = knob.frame
            // The scroller is flipped, the terminal (and this context) isn't.
            if layer.isGeometryFlipped { frame.origin.y = layer.bounds.height - frame.maxY }
            frame = frame.offsetBy(dx: scroller.frame.minX, dy: scroller.frame.minY)
            context.saveGState()
            context.setAlpha(opacity)
            context.setFillColor(color)
            context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius,
                                   transform: nil))
            context.fillPath()
            context.restoreGState()
        }
    }
}
