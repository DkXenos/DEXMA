import SwiftUI

/// Puts the session's long-lived terminal into the SwiftUI tree. `makeNSView` hands back the
/// same instance every time, so the terminal is never recreated.
struct TerminalHost: NSViewRepresentable {
    let session: ShellSession
    let shape: NotchShape
    let panelSize: CGSize
    let origin: CGPoint
    let opacity: CGFloat

    func makeNSView(context: Context) -> TerminalContainerView {
        session.container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.update(mask: shape, panelSize: panelSize, origin: origin, opacity: opacity)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalContainerView,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
