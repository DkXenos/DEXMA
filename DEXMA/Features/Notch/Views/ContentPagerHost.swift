import SwiftUI

/// Puts the long-lived content pager (and with it the terminal and the web views) into the
/// SwiftUI tree. `makeNSView` hands back the same instance every time: nothing is recreated.
struct ContentPagerHost: NSViewRepresentable {
    let pager: ContentPagerView
    let shape: NotchShape
    let panelSize: CGSize
    let origin: CGPoint
    let opacity: CGFloat

    func makeNSView(context: Context) -> ContentPagerView {
        pager
    }

    func updateNSView(_ nsView: ContentPagerView, context: Context) {
        nsView.update(mask: shape, panelSize: panelSize, origin: origin, opacity: opacity)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ContentPagerView,
                      context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
