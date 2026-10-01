import AppKit

/// Where the notch is on a screen, and the fixed window frame the panel lives in.
/// Rects are in global AppKit screen coordinates (bottom-left origin).
struct NotchGeometry: Equatable {
    static let defaultExpandedSize = CGSize(width: 680, height: 400)
    /// Transparent slack around the expanded shape for its ears and spring overshoot.
    static let margin: CGFloat = 40
    /// Concave flare where the expanded silhouette meets the screen edge.
    static let earRadius: CGFloat = 12
    /// The pill shown on screens without a notch.
    static let pillWidth: CGFloat = 150

    let screenFrame: CGRect
    /// The physical notch, or a pill centered at the top of a notch-less screen.
    let notchRect: CGRect
    let hasNotch: Bool
    let expandedSize: CGSize

    init(screenFrame: CGRect, notchRect: CGRect, hasNotch: Bool, expandedSize: CGSize) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
        self.expandedSize = expandedSize
    }

    init(screen: NSScreen, expandedSize: CGSize = defaultExpandedSize) {
        let frame = screen.frame
        // The auxiliary areas are the menu bar strips left and right of the camera housing;
        // the notch is the gap between them. Both are nil on screens without a notch.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let height = screen.safeAreaInsets.top
            self.init(screenFrame: frame,
                      notchRect: CGRect(x: left.maxX, y: frame.maxY - height,
                                        width: right.minX - left.maxX, height: height),
                      hasNotch: true, expandedSize: expandedSize)
        } else {
            // Match the menu bar height so the pill sits inside it.
            let menuBar = frame.maxY - screen.visibleFrame.maxY
            let height = menuBar > 12 ? menuBar - 4 : 22
            self.init(screenFrame: frame,
                      notchRect: CGRect(x: frame.midX - Self.pillWidth / 2, y: frame.maxY - height,
                                        width: Self.pillWidth, height: height),
                      hasNotch: false, expandedSize: expandedSize)
        }
    }

    /// Big enough for the expanded panel plus margin, centered on the notch and flush with
    /// the top of the screen, i.e. overlapping the menu bar.
    var panelFrame: CGRect {
        let width = expandedSize.width + 2 * Self.margin
        let height = expandedSize.height + Self.margin
        // Whole-point origin, so the window lands exactly where we ask on any display.
        let x = (notchRect.midX - width / 2).rounded(.down)
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Notch center in the panel's own coordinates. Not simply `width / 2`: the notch is
    /// often off-center by half a point, and the panel origin is rounded to whole points.
    var notchCenterXInPanel: CGFloat {
        notchRect.midX - panelFrame.minX
    }

    /// The biggest silhouette (body width, height) the panel window can show without cutting
    /// it off, with `inset` points to spare on each side (beyond the ears) and below.
    func silhouetteLimit(inset: CGFloat = 1) -> CGSize {
        let panel = panelFrame.size
        let halfWidth = min(notchCenterXInPanel, panel.width - notchCenterXInPanel)
        return CGSize(width: 2 * (halfWidth - inset - Self.earRadius), height: panel.height - inset)
    }

    /// The silhouette at `progress` (0 = notch, 1 = expanded; may overshoot either way).
    func shape(at progress: CGFloat) -> NotchShape {
        // Closed: slightly rounder than the physical notch so no corner pixel peeks out.
        // No notch: a pill with fully rounded ends.
        let closedRadius = hasNotch ? 9 : notchRect.height / 2
        let p = max(progress, 0)
        return NotchShape(
            width: Self.overshoot(lerp(notchRect.width, expandedSize.width, p),
                                  past: expandedSize.width, upTo: silhouetteLimit().width),
            height: Self.overshoot(lerp(notchRect.height, expandedSize.height, p),
                                   past: expandedSize.height, upTo: silhouetteLimit().height),
            bottomRadius: lerp(closedRadius, 26, min(p, 1)),
            earRadius: lerp(0, Self.earRadius, min(p, 1)),
            centerX: notchCenterXInPanel)
    }

    /// Past fully open (spring overshoot after a fast flick), growth eases into the room the
    /// window has instead of running past its edge, where it would be cut off in a straight
    /// line. Small overshoots are unchanged (tanh x ≈ x); at or below `size`, nothing changes.
    private static func overshoot(_ value: CGFloat, past size: CGFloat, upTo limit: CGFloat) -> CGFloat {
        let room = limit - size
        guard value > size, room > 0 else { return value }
        return size + room * CGFloat(tanh(Double((value - size) / room)))
    }

    /// Where the terminal sits inside the panel (top-left origin): below the notch strip,
    /// inset from the expanded body's edges. It never moves or resizes while animating.
    var terminalFrame: CGRect {
        let inset: CGFloat = 16
        let top = notchRect.height + 6
        return CGRect(x: notchCenterXInPanel - expandedSize.width / 2 + inset, y: top,
                      width: expandedSize.width - 2 * inset,
                      height: expandedSize.height - top - inset + 2)
    }

    /// Where the pointer counts as over the notch (global coordinates): the notch plus a
    /// little slack; while peeking, the swollen shape too, so the pointer doesn't flicker in
    /// and out at its edge.
    func hoverZone(peeking: Bool) -> CGRect {
        let grow: CGFloat = peeking ? 24 : 6
        return CGRect(x: notchRect.minX - grow, y: notchRect.minY - grow,
                      width: notchRect.width + 2 * grow, height: notchRect.height + grow + 1)
    }
}
