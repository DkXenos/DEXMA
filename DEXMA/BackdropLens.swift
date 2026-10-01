import AppKit

/// Bends the screen around the moving notch: a ring of clear Liquid Glass (macOS 26) behind
/// the black silhouette, a little larger than it. The window server refracts whatever is
/// behind the panel (desktop, menu bar, other apps) through the ring, most strongly at its
/// edge, with no capture and no Screen Recording permission. Only while moving: at rest it's
/// hidden, so it isn't rendered at all. On older macOS this does nothing.
final class BackdropLens {
    private let glass: NSView?

    /// Whether this macOS has Liquid Glass to bend the screen with.
    var isAvailable: Bool { glass != nil }
    /// The glass is on screen (only while moving).
    var isShowing: Bool { glass.map { !$0.isHidden } ?? false }

    /// Adds the glass to `container` (flipped, panel coordinates), below everything else.
    init(in container: NSView) {
        if #available(macOS 26, *) {
            let view = NSGlassEffectView()
            view.style = .clear
            view.isHidden = true
            container.addSubview(view, positioned: .below, relativeTo: nil)
            glass = view
        } else {
            glass = nil
        }
    }

    /// `silhouette`: the notch body this frame (panel coordinates, top-left origin, hanging
    /// from y = 0) and its bottom corner radius. `ring`: how far the glass reaches past it.
    func update(silhouette: CGRect, radius: CGFloat, ring: CGFloat) {
        guard let glass else { return }
        // Under a quarter point the ring can't be seen; hidden means not rendered at all.
        guard ring > 0.25 else {
            if !glass.isHidden { glass.isHidden = true }
            return
        }
        let corner = radius + ring
        // Reaches above the window's top edge, so its top corners are cut off and the ring
        // flows into the screen edge like the silhouette does.
        let frame = CGRect(x: silhouette.minX - ring, y: -corner,
                           width: silhouette.width + 2 * ring,
                           height: silhouette.maxY + ring + corner)
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // Follows the spring frame by frame, no easing.
        if glass.frame != frame { glass.frame = frame }
        if #available(macOS 26, *), let view = glass as? NSGlassEffectView, view.cornerRadius != corner {
            view.cornerRadius = corner
        }
        // Fades in over the first few points, so it never pops in as a hairline.
        glass.alphaValue = min(1, (ring - 0.25) / 4)
        if glass.isHidden { glass.isHidden = false }
        CATransaction.commit()
    }

    /// Shows the glass for a moment at launch, entirely behind the closed notch's black
    /// silhouette (invisible), so the window server has built it before the first open.
    func warmUp(behind silhouette: CGRect) {
        guard let glass, silhouette.width > 8, silhouette.height > 8 else { return }
        glass.frame = silhouette.insetBy(dx: 4, dy: 4)
        glass.alphaValue = 1
        glass.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak glass] in
            glass?.isHidden = true
        }
    }
}

/// The panel's content view: the backdrop lens below, the SwiftUI content above. Flipped,
/// so subviews use the same top-left coordinates as the SwiftUI layout.
final class PanelContentView: NSView {
    override var isFlipped: Bool { true }
}
