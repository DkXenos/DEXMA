import SwiftUI

/// SwiftUI root of the panel. Everything derives from `controller.progress`; nothing here
/// animates on its own.
struct NotchContentView: View {
    let controller: PanelController
    let session: ShellSession

    var body: some View {
        let geometry = controller.geometry
        let progress = controller.progress
        let shape = geometry.shape(at: progress)
        let panel = geometry.panelFrame.size
        let terminal = geometry.terminalFrame
        // Text fades in once the silhouette is mostly open, so it never floats in a sliver.
        let contentOpacity = min(max((progress - 0.35) / 0.5, 0), 1)

        ZStack(alignment: .topLeading) {
            shape.fill(.black)
            TerminalHost(session: session, shape: shape, panelSize: panel,
                         origin: terminal.origin, opacity: contentOpacity)
                .frame(width: terminal.width, height: terminal.height)
                .offset(x: terminal.minX, y: terminal.minY)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
