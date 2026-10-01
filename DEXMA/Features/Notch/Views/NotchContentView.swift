import SwiftUI

/// SwiftUI root of the panel. Everything derives from the view model's `progress` (and, while
/// the liquid effect runs, its `effects`); nothing here animates on its own.
///
/// The black silhouette is always this one vector shape; the effect only squashes and
/// stretches it through its size (exactly 1 × 1 at rest). While moving, the motion layer's
/// snapshot stands in for the selected tab's live content; both switch in the same update.
/// The band beside the notch stays live, scaled with the silhouette.
struct NotchContentView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let silhouette = viewModel.silhouette
        let panel = geometry.panelFrame.size
        let content = geometry.contentFrame
        let contentOpacity = viewModel.contentOpacity
        let moving = viewModel.effects.isActive
        let tab = viewModel.tab

        ZStack(alignment: .topLeading) {
            silhouette.shape.fill(.black)
            // Faded out (via their mask layers) rather than hidden while moving, so the selected
            // one stays first responder and keeps taking typing during the animation.
            TerminalHost(session: viewModel.session, shape: silhouette.shape, panelSize: panel,
                         origin: content.origin,
                         opacity: moving || tab != .terminal ? 0 : contentOpacity)
                .frame(width: content.width, height: content.height)
                .offset(x: content.minX, y: content.minY)
            SearchHost(session: viewModel.search.session, shape: silhouette.shape, panelSize: panel,
                       origin: content.origin,
                       opacity: moving || tab != .search ? 0 : contentOpacity)
                .frame(width: content.width, height: content.height)
                .offset(x: content.minX, y: content.minY)
            LiquidMotionLayer(effects: viewModel.effects, shape: silhouette.shape,
                              scale: silhouette.scale, progress: viewModel.progress,
                              panelSize: panel, contentFrame: content,
                              contentOpacity: contentOpacity)
            NotchBand(viewModel: viewModel)
                // The same squash and stretch as the content's (LiquidEffects.metal's
                // liquidStretch), as a plain transform.
                .scaleEffect(x: silhouette.scale.width, y: silhouette.scale.height,
                             anchor: UnitPoint(x: silhouette.shape.centerX / max(panel.width, 1), y: 0))
                .opacity(contentOpacity)
                .clipShape(silhouette.shape)
                .allowsHitTesting(viewModel.state == .open)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
