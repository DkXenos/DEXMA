import SwiftUI

/// SwiftUI root of the panel. Everything derives from the view model's `progress` (and, while
/// the liquid effect runs, its `effects`); nothing here animates on its own.
///
/// The black silhouette is always this one vector shape; the effect only squashes and
/// stretches it through its size (exactly 1 × 1 at rest). While moving, the motion layer's
/// snapshot stands in for the selected tab's live content; both switch in the same update.
/// The chrome (band, card stroke, page dots) is live at rest and copied into the motion layer
/// while moving, so the distortion bends it too.
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
                              contentOpacity: contentOpacity) {
                NotchChrome(viewModel: viewModel)
            }
            // The live chrome, out of any shader (so hovering or swiping costs no shader pass),
            // flattened so its text renders exactly like its copy in the motion layer: the two
            // swap without a visible change.
            NotchChrome(viewModel: viewModel)
                .compositingGroup()
                .opacity(moving ? 0 : contentOpacity)
                .clipShape(silhouette.shape)
                .allowsHitTesting(viewModel.state == .open)
            // The Devices connect peek: on the pill grown out of the notch, squashed and
            // stretched with it.
            if let activity = viewModel.activity, let layout = viewModel.activityLayout {
                DeviceActivityView(activity: activity, layout: layout)
                    .frame(width: panel.width, height: panel.height, alignment: .topLeading)
                    .scaleEffect(x: silhouette.scale.width, y: silhouette.scale.height,
                                 anchor: UnitPoint(x: geometry.notchCenterXInPanel / max(panel.width, 1), y: 0))
                    .opacity(viewModel.activityContentOpacity)
                    .clipShape(silhouette.shape)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
