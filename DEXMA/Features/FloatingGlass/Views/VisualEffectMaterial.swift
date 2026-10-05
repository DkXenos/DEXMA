import SwiftUI

/// Before macOS 26: the system's popover material behind the window (blurred desktop and windows
/// behind), standing in for Liquid Glass. It follows light/dark, Reduce Transparency and
/// Increase Contrast by itself.
struct VisualEffectMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // Always active: the window belongs to an app that's rarely frontmost.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
