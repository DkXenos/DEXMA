import SwiftUI

/// SwiftUI root of the panel. Everything derives from the view model's `progress` (and, while
/// the liquid effect runs, its `effects`); nothing here animates on its own.
///
/// The black silhouette is always this one vector shape; the effect only squashes and
/// stretches it through its size (exactly 1 × 1 at rest). While moving, the motion layer's
/// snapshot stands in for the live terminal; both switch in the same update.
struct NotchContentView: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let silhouette = viewModel.silhouette
        let panel = geometry.panelFrame.size
        let terminal = geometry.terminalFrame
        let contentOpacity = viewModel.contentOpacity
        let moving = viewModel.effects.isActive

        ZStack(alignment: .topLeading) {
            silhouette.shape.fill(.black)
            // Faded out (via its mask layer) rather than hidden while moving, so it stays
            // first responder and keeps taking typing during the animation.
            TerminalHost(session: viewModel.session, shape: silhouette.shape, panelSize: panel,
                         origin: terminal.origin, opacity: moving ? 0 : contentOpacity)
                .frame(width: terminal.width, height: terminal.height)
                .offset(x: terminal.minX, y: terminal.minY)
            LiquidMotionLayer(effects: viewModel.effects, shape: silhouette.shape,
                              scale: silhouette.scale, progress: viewModel.progress,
                              panelSize: panel, terminalFrame: terminal,
                              contentOpacity: contentOpacity)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
