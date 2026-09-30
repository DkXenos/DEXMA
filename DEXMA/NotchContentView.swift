import SwiftUI

/// SwiftUI root of the panel. Everything derives from `controller.progress` (and, while the
/// liquid effect runs, `controller.effects`); nothing here animates on its own.
///
/// The black silhouette is always this one vector shape; the effect only squashes and
/// stretches it through its size (exactly 1 × 1 at rest). While moving, the motion layer's
/// snapshot stands in for the live terminal; both switch in the same update.
struct NotchContentView: View {
    let controller: PanelController
    let session: ShellSession

    var body: some View {
        let geometry = controller.geometry
        let progress = controller.progress
        let effects = controller.effects
        let base = geometry.shape(at: progress)
        let scale = effects.frame.scale(width: base.width, height: base.height)
        let shape = base.scaled(by: scale)
        let panel = geometry.panelFrame.size
        let terminal = geometry.terminalFrame
        // Text fades in once the silhouette is mostly open, so it never floats in a sliver.
        let contentOpacity = min(max((progress - 0.35) / 0.5, 0), 1)
        let moving = effects.isActive

        ZStack(alignment: .topLeading) {
            shape.fill(.black)
            // Faded out (via its mask layer) rather than hidden while moving, so it stays
            // first responder and keeps taking typing during the animation.
            TerminalHost(session: session, shape: shape, panelSize: panel,
                         origin: terminal.origin, opacity: moving ? 0 : contentOpacity)
                .frame(width: terminal.width, height: terminal.height)
                .offset(x: terminal.minX, y: terminal.minY)
            LiquidMotionLayer(effects: effects, shape: shape, scale: scale, progress: progress,
                              panelSize: panel, terminalFrame: terminal,
                              contentOpacity: contentOpacity)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
