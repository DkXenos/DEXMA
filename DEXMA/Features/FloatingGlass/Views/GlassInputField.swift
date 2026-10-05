import SwiftUI

/// The question field (`GlassTextView`, made once by the view model) in the glass capsule. SwiftUI
/// sizes it: its width from the capsule, its height `height` (the text's lines).
struct GlassInputField: NSViewRepresentable {
    let textView: GlassTextView
    let height: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        textView.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? GlassMetrics.fieldWidth, height: height)
    }
}
