import AppKit
import SwiftUI

/// The Devices tab's page in the content pager: the SwiftUI page in a hosting view at the
/// card's size. It takes the keyboard while its tab is selected (so typing isn't sent anywhere
/// else) and ignores it: the panel's own shortcuts (Esc, ⌘-keys, ⌃Tab) are handled before.
final class DevicesCardView: NSView {
    private let hosting: NSHostingView<DevicesPageView>

    init(viewModel: DevicesViewModel, size: CGSize) {
        hosting = NSHostingView(rootView: DevicesPageView(viewModel: viewModel))
        super.init(frame: CGRect(origin: .zero, size: size))
        hosting.sizingOptions = []  // The pager sizes it; SwiftUI must never resize it.
        hosting.safeAreaRegions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {}
}
