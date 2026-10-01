import SwiftUI

/// The tab segments left of the notch, with the selection indicator behind the selected one.
/// Labelled when there's room for it, icons only in a narrow panel. The indicator slides like a
/// droplet (`BandMotion`): stretched along its motion, squashed as it lands, 1 × 1 at rest.
struct TabBand: View {
    static let segmentHeight: CGFloat = 24
    static let labelledWidth: CGFloat = 92
    static let iconWidth: CGFloat = 36
    static let spacing: CGFloat = 4

    let selected: PanelTab
    let band: BandMotion
    let size: CGSize
    let select: (PanelTab) -> Void

    var body: some View {
        let tabs = PanelTab.allCases
        let labelled = size.width >= CGFloat(tabs.count) * Self.labelledWidth
            + CGFloat(tabs.count - 1) * Self.spacing
        let segment = CGSize(width: labelled ? Self.labelledWidth : Self.iconWidth, height: Self.segmentHeight)
        let indicator = band.indicator

        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: segment.width, height: segment.height)
                .scaleEffect(x: indicator.scale.width, y: indicator.scale.height)
                .offset(x: indicator.position * (segment.width + Self.spacing))
            HStack(spacing: Self.spacing) {
                ForEach(tabs, id: \.self) { tab in
                    Button { select(tab) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                            if labelled { Text(tab.title).font(.system(size: 12, weight: .medium)) }
                        }
                        .foregroundStyle(.white.opacity(tab == selected ? 0.95 : 0.55))
                    }
                    .buttonStyle(BandButtonStyle(lens: band.lens(for: "tab.\(tab)"), size: segment))
                    .help("\(tab.title) (⌘\((tabs.firstIndex(of: tab) ?? 0) + 1))")
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}
