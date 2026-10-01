import SwiftUI

/// SwiftUI root of the panel. Everything derives from the view model's `progress` (and, while
/// the liquid effect runs, its `effects`); nothing here animates on its own.
///
/// The black silhouette is always this one vector shape; the effect only squashes and
/// stretches it through its size (exactly 1 × 1 at rest). While moving, the motion layer's
/// snapshot stands in for the selected tab's live content; both switch in the same update.
/// The chrome (band, card stroke, page dots) lives in the motion layer, moving or not.
struct NotchContentView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let silhouette = viewModel.silhouette
        let panel = geometry.panelFrame.size
        let content = geometry.contentFrame
        let contentOpacity = viewModel.contentOpacity
        let moving = viewModel.effects.isActive

        ZStack(alignment: .topLeading) {
            silhouette.shape.fill(.black)
            // Faded out (via its mask layer) rather than hidden while moving, so the selected
            // page stays first responder and keeps taking typing during the animation.
            ContentPagerHost(pager: viewModel.pager, shape: silhouette.shape, panelSize: panel,
                             origin: content.origin, opacity: moving ? 0 : contentOpacity)
                .frame(width: content.width, height: content.height)
                .offset(x: content.minX, y: content.minY)
            LiquidMotionLayer(effects: viewModel.effects, shape: silhouette.shape,
                              scale: silhouette.scale, progress: viewModel.progress,
                              panelSize: panel, contentFrame: content,
                              contentOpacity: contentOpacity,
                              chromeInteractive: viewModel.state == .open) {
                NotchChrome(viewModel: viewModel)
            }
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
