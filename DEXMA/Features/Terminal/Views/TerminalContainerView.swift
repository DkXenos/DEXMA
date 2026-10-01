import AppKit
import SwiftTerm

/// Holds the terminal at a fixed size as the terminal tab's page in the content pager (which
/// clips it to the card and the notch silhouette), so opening, closing and swiping between
/// tabs never resize or re-lay-out the terminal.
final class TerminalContainerView: NSView {
    let terminalView: LocalProcessTerminalView

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: terminalView.frame)
        wantsLayer = true
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
