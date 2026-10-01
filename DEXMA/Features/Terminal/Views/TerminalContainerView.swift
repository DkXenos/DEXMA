import AppKit
import SwiftTerm
import SwiftUI

/// Holds the terminal at a fixed size and clips it to the notch silhouette with a layer mask,
/// so opening and closing never resizes or re-lays-out the terminal.
final class TerminalContainerView: NSView {
    let terminalView: LocalProcessTerminalView
    private let maskLayer = CAShapeLayer()

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: terminalView.frame)
        wantsLayer = true
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
        layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clips to `shape`, which is laid out in panel coordinates (top-left origin); this view's
    /// top-left corner sits at `origin` in those coordinates.
    /// Called from SwiftUI's update pass, so it only touches layers: changing NSView
    /// properties (isHidden, alphaValue) here makes SwiftUI re-enter layout.
    func update(mask shape: NotchShape, panelSize: CGSize, origin: CGPoint, opacity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        // Panel coordinates are y-down; this (unflipped) view's layer is y-up.
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                          tx: -origin.x, ty: bounds.height + origin.y)
        let path = shape.path(in: CGRect(origin: .zero, size: panelSize)).cgPath
        maskLayer.path = path.copy(using: &transform)
        // The mask's opacity scales the content's alpha: that's the fade.
        maskLayer.opacity = Float(opacity)
        CATransaction.commit()
    }
}
