import AppKit
import Observation
import SwiftUI

/// The Devices tab for the panel: its page (`card`: devices and the Controls card) and its
/// picture for the liquid effect.
/// `cacheDisplay` can't draw SwiftUI text, so the picture is the same SwiftUI page rendered off
/// screen (`ImageRenderer`), taken while idle like the other tabs' (it changes only when a
/// device or a relative time does: a few times an hour at most).
final class DevicesPage: MotionContent {
    let card: DevicesCardView
    /// What the page shows changed (levels, devices, a relative time).
    var onChange: (() -> Void)?
    var onSnapshotRefreshed: (() -> Void)?

    private let viewModel: DevicesViewModel
    private let controls: QuickControlsViewModel
    private var cachedSnapshot: ContentSnapshot?

    init(viewModel: DevicesViewModel, controls: QuickControlsViewModel, size: CGSize) {
        self.viewModel = viewModel
        self.controls = controls
        card = DevicesCardView(viewModel: viewModel, controls: controls, size: size)
        observe()
    }

    /// The tab came to rest on screen: catch up with brightness changed elsewhere.
    func didShow() {
        controls.refresh()
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

    /// Only the sliders react to input, and they change the view models, which `observe` sees.
    func isChanged(by type: NSEvent.EventType) -> Bool {
        false
    }

    func didReappear() -> Bool {
        false
    }

    #if DEBUG
    var debugControls: QuickControlsViewModel { controls }
    #endif

    // MARK: Private

    private func render() -> ContentSnapshot? {
        let size = card.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = ImageRenderer(content: DevicesPageView(viewModel: viewModel, controls: controls)
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
            _ = controls.brightness
            _ = controls.volume
            _ = controls.isMuted
            _ = controls.canSetVolume
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
                self?.observe()
            }
        }
    }
}
