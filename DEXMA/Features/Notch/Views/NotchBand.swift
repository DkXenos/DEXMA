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
            TabBand(selected: viewModel.tab, band: viewModel.band, size: tabs.size) { tab in
                viewModel.click { viewModel.select(tab) }
            }
            .offset(x: tabs.minX, y: tabs.minY)
            if viewModel.tab == .search {
                SearchActionsBand(search: viewModel.search, band: viewModel.band, size: actions.size) { action in
                    viewModel.click(action)
                }
                .offset(x: actions.minX, y: actions.minY)
            }
        }
        .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
    }
}
