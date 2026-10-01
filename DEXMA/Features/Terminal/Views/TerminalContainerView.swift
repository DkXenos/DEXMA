import AppKit
import SwiftTerm

/// Holds the terminal at a fixed size as the terminal tab's page in the content pager (which
/// clips it to the card and the notch silhouette), so opening, closing and swiping between
/// tabs never resize or re-lay-out the terminal.
final class TerminalContainerView: NSView {
    /// Room between the card's edges and the text (left, top, right with the scroller, bottom).
    static let padding = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 6)

    let terminalView: LocalProcessTerminalView

    init(size: CGSize, terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        let p = Self.padding
        terminalView.frame = CGRect(x: p.left, y: p.bottom, width: max(size.width - p.left - p.right, 0),
                                    height: max(size.height - p.top - p.bottom, 0))
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
    }

    /// The terminal view's top-left corner in the card (top-left origin).
    var terminalOrigin: CGPoint {
        CGPoint(x: terminalView.frame.minX, y: bounds.height - terminalView.frame.maxY)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
