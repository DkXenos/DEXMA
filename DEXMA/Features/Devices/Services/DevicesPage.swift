import AppKit
import Observation
import SwiftUI

/// The Devices tab for the panel: its page (`card`) and its picture for the liquid effect.
/// `cacheDisplay` can't draw SwiftUI text, so the picture is the same SwiftUI page rendered off
/// screen (`ImageRenderer`), taken while idle like the other tabs' (it changes only when a
/// device or a relative time does: a few times an hour at most).
final class DevicesPage: MotionContent {
    let card: DevicesCardView
    /// What the page shows changed (levels, devices, a relative time).
    var onChange: (() -> Void)?
    var onSnapshotRefreshed: (() -> Void)?

    private let viewModel: DevicesViewModel
    private var cachedSnapshot: ContentSnapshot?

    init(viewModel: DevicesViewModel, size: CGSize) {
        self.viewModel = viewModel
        card = DevicesCardView(viewModel: viewModel, size: size)
        observe()
    }

    func resize(to size: CGSize) {
        guard card.frame.size != size else { return }
        card.setFrameSize(size)
    }

    // MARK: MotionContent

    func motionSnapshot() -> ContentSnapshot? {
        if cachedSnapshot == nil { cachedSnapshot = render() }
        return cachedSnapshot
    }

    func invalidateSnapshot() {
        cachedSnapshot = nil
    }

    func refreshSnapshot() {
        _ = motionSnapshot()
    }

    /// Nothing on the page reacts to input.
    func isChanged(by type: NSEvent.EventType) -> Bool {
        false
    }

    func didReappear() -> Bool {
        false
    }

    // MARK: Private

    private func render() -> ContentSnapshot? {
        let size = card.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = ImageRenderer(content: DevicesPageView(viewModel: viewModel)
            .frame(width: size.width, height: size.height))
        let scale = card.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage.map { ContentSnapshot(image: $0, scale: scale) }
    }

    /// Whatever the page reads: a change means the picture is stale.
    private func observe() {
        withObservationTracking {
            _ = viewModel.devices
            _ = viewModel.now
            _ = viewModel.isBluetoothDenied
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
                self?.observe()
            }
        }
    }
}
