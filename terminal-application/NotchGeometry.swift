import AppKit

/// Where the notch is on a screen, and the fixed window frame the panel lives in.
/// Rects are in global AppKit screen coordinates (bottom-left origin).
struct NotchGeometry: Equatable {
    /// Fully expanded panel. Placeholder until Phase 3 sizes it to the terminal grid.
    static let expandedSize = CGSize(width: 640, height: 380)
    /// Transparent slack around the expanded shape for spring overshoot (and later, shadow).
    static let margin: CGFloat = 32
    /// Virtual notch for screens without one (the 14" MacBook Pro notch).
    static let fallbackNotchSize = CGSize(width: 185, height: 32)

    let screenFrame: CGRect
    /// The physical notch, or a virtual one centered at the top of a notch-less screen.
    let notchRect: CGRect
    let hasNotch: Bool

    init(screen: NSScreen) {
        let frame = screen.frame
        screenFrame = frame
        // The auxiliary areas are the menu bar strips left and right of the camera housing;
        // the notch is the gap between them. Both are nil on screens without a notch.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let height = screen.safeAreaInsets.top
            notchRect = CGRect(x: left.maxX, y: frame.maxY - height,
                               width: right.minX - left.maxX, height: height)
            hasNotch = true
        } else {
            let size = Self.fallbackNotchSize
            notchRect = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                               width: size.width, height: size.height)
            hasNotch = false
        }
    }

    /// Big enough for the expanded panel plus margin, centered on the notch and flush with
    /// the top of the screen, i.e. overlapping the menu bar.
    var panelFrame: CGRect {
        let width = Self.expandedSize.width + 2 * Self.margin
        let height = Self.expandedSize.height + Self.margin
        // Whole-point origin, so the window lands exactly where we ask on any display.
        let x = (notchRect.midX - width / 2).rounded(.down)
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Notch center in the panel's own coordinates. Not simply `width / 2`: the notch is
    /// often off-center by half a point, and the panel origin is rounded to whole points.
    var notchCenterXInPanel: CGFloat {
        notchRect.midX - panelFrame.minX
    }

    /// The screen with a notch (the built-in display, often not the primary screen),
    /// else the primary screen. Multi-display policy comes in Phase 7.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
}
