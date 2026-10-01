import AppKit
import SwiftUI

/// The tab switcher left of the notch, an expanding pill like the Dynamic Island: the selected
/// tab shows icon + label, the others their icon, the indicator sits behind the selected one.
/// Widths, label reveal, indicator and colours all follow the panel's tab progress
/// (`TabSwitcherLayout`), so half a swipe shows a half-expanded state; the indicator also
/// stretches like a droplet as it moves (`BandMotion`).
struct TabSwitcher: View {
    static let labelFont = NSFont.systemFont(ofSize: TabSwitcherLayout.labelSize, weight: .semibold)

    let selected: PanelTab
    let progress: CGFloat
    let band: BandMotion
    /// The band region it lives in (its width decides whether labels fit).
    let available: CGFloat
    let select: (PanelTab) -> Void

    var body: some View {
        let tabs = PanelTab.allCases
        let widths = tabs.map { tab in
            TabSwitcherLayout.activeWidth(labelWidth: (tab.title as NSString)
                .size(withAttributes: [.font: Self.labelFont]).width)
        }
        let layout = TabSwitcherLayout(activeWidths: widths, progress: progress, available: available)
        let stretch = band.indicator.scale

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TabSwitcherLayout.cornerRadius, style: .continuous)
                .fill(.white.opacity(0.07))
                .frame(width: layout.size.width, height: layout.size.height)
            RoundedRectangle(cornerRadius: TabSwitcherLayout.indicatorRadius, style: .continuous)
                .fill(.white.opacity(0.17))
                .frame(width: layout.indicator.width, height: layout.indicator.height)
                .scaleEffect(x: stretch.width, y: stretch.height)
                .offset(x: layout.indicator.minX, y: layout.indicator.minY)
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let item = layout.tabs[index]
                Button { select(tab) } label: {
                    TabLabel(tab: tab, reveal: item.reveal, labelled: layout.labelled, width: item.frame.width)
                }
                .buttonStyle(BandButtonStyle(lens: band.lens(for: "tab.\(tab)"), size: item.frame.size,
                                             cornerRadius: TabSwitcherLayout.indicatorRadius))
                .offset(x: item.frame.minX, y: item.frame.minY)
                .help("\(tab.title) (⌘\(index + 1))")
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

/// One tab's icon and (revealed with the tab progress) label.
private struct TabLabel: View {
    let tab: PanelTab
    let reveal: CGFloat
    let labelled: Bool
    let width: CGFloat

    var body: some View {
        let box = TabSwitcherLayout.iconBox
        let inactiveX = (TabSwitcherLayout.inactiveWidth - box) / 2
        let iconX = labelled ? inactiveX + (TabSwitcherLayout.labelPadding - inactiveX) * reveal : inactiveX
        ZStack(alignment: .leading) {
            Image(systemName: tab.symbol)
                .font(.system(size: TabSwitcherLayout.iconSize, weight: .semibold))
                .frame(width: box)
                .foregroundStyle(.white.opacity(0.55 + 0.45 * reveal))
                .offset(x: iconX)
            if labelled {
                Text(tab.title)
                    .font(.system(size: TabSwitcherLayout.labelSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .opacity(reveal)
                    // Slides in a little as it fades in.
                    .offset(x: TabSwitcherLayout.labelPadding + box + TabSwitcherLayout.iconLabelSpacing
                                - 4 * (1 - reveal))
            }
        }
        .frame(width: width, height: TabSwitcherLayout.tabHeight, alignment: .leading)
        .clipped()
    }
}
