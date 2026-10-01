import SwiftUI

/// The strip beside the notch, laid out over the whole panel: the tabs left of the notch, the
/// selected tab's buttons right of it.
struct NotchBand: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let tabs = geometry.tabBandFrame
        let actions = geometry.actionBandFrame

        ZStack(alignment: .topLeading) {
            TabBand(selected: viewModel.tab, progress: viewModel.tabProgress, band: viewModel.band,
                    size: tabs.size) { tab in
                viewModel.click { viewModel.select(tab) }
            }
            .offset(x: tabs.minX, y: tabs.minY)
            // Crossfades with the swipe: fully there on the Search tab, gone a page away.
            let searchShown = max(0, 1 - abs(viewModel.tabProgress - 1))
            SearchActionsBand(search: viewModel.search, band: viewModel.band, size: actions.size) { action in
                viewModel.click(action)
            }
            .opacity(searchShown)
            .allowsHitTesting(viewModel.tab == .search)
            .offset(x: actions.minX, y: actions.minY)
        }
        .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
    }
}
