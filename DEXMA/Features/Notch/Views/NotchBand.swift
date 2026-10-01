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
            TabBand(selected: viewModel.tab, size: tabs.size) { viewModel.select($0) }
                .offset(x: tabs.minX, y: tabs.minY)
            if viewModel.tab == .search {
                SearchActionsBand(search: viewModel.search, size: actions.size)
                    .offset(x: actions.minX, y: actions.minY)
            }
        }
        .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
    }
}
