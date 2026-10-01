import SwiftUI

/// Puts the session's long-lived Search card into the SwiftUI tree. `makeNSView` hands back
/// the same instance every time, so the web view is never recreated.
struct SearchHost: NSViewRepresentable {
    let session: SearchSession
    let shape: NotchShape
    let panelSize: CGSize
    let origin: CGPoint
    let opacity: CGFloat

    func makeNSView(context: Context) -> SearchCardView {
        session.card
    }

    func updateNSView(_ nsView: SearchCardView, context: Context) {
        nsView.update(mask: shape, panelSize: panelSize, origin: origin, opacity: opacity)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SearchCardView,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
