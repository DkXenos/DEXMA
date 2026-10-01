import SwiftUI

/// Everything drawn around the content: the band (tab switcher left of the notch, the selected
/// tab's context right of it, the capture controls at its end), the card's stroke and highlight,
/// and the page dots. One
/// instance, inside the motion layer, so the open/close distortion bends it with the content
/// and nothing is ever swapped for a picture of it. Laid out over the whole panel.
struct NotchChrome: View {
    let viewModel: NotchViewModel

    var body: some View {
        let geometry = viewModel.geometry
        let tabs = geometry.tabBandFrame
        let card = geometry.contentFrame

        ZStack(alignment: .topLeading) {
            TabSwitcher(selected: viewModel.tab, progress: viewModel.tabProgress, band: viewModel.band,
                        available: tabs.width) { tab in
                viewModel.click { viewModel.select(tab) }
            }
            .offset(x: tabs.minX, y: (geometry.bandHeight - TabSwitcherLayout.tabHeight) / 2
                        - TabSwitcherLayout.padding)
            BandContext(viewModel: viewModel)
            if let capture = viewModel.capture {
                CaptureControls(capture: capture, band: viewModel.band, region: geometry.actionBandFrame) { action in
                    viewModel.click(action)
                }
            }
            CardDecoration(size: card.size)
                .offset(x: card.minX, y: card.minY)
            PageDots(count: PanelTab.allCases.count, progress: viewModel.tabProgress,
                     center: geometry.pageDotsCenter)
        }
        .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
    }
}
