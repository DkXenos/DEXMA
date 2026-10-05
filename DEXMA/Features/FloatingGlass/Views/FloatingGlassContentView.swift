import AppKit
import SwiftUI

/// The floating glass panel's content: the SwiftUI glass (`root`) filling the window, and AppKit
/// overlays above it (web content can't live inside a SwiftUI glass effect's offscreen pass).
final class FloatingGlassContentView: NSView {
    init<Root: View>(root: Root) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []  // Fixed-size window: SwiftUI must never resize it.
        hosting.safeAreaRegions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func addOverlay(_ view: NSView) {
        addSubview(view)
    }
}
