import SwiftUI

/// The tab segments left of the notch, with the selection indicator behind the selected one.
/// Labelled when there's room for it, icons only in a narrow panel.
struct TabBand: View {
    static let segmentHeight: CGFloat = 24
    static let labelledWidth: CGFloat = 92
    static let iconWidth: CGFloat = 36
    static let spacing: CGFloat = 4

    let selected: PanelTab
    let size: CGSize
    let select: (PanelTab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tabs = PanelTab.allCases
        let labelled = size.width >= CGFloat(tabs.count) * Self.labelledWidth
            + CGFloat(tabs.count - 1) * Self.spacing
        let width = labelled ? Self.labelledWidth : Self.iconWidth
        let index = CGFloat(tabs.firstIndex(of: selected) ?? 0)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: width, height: Self.segmentHeight)
                .offset(x: index * (width + Self.spacing))
                .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: index)
            HStack(spacing: Self.spacing) {
                ForEach(tabs, id: \.self) { tab in
                    Button { select(tab) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                            if labelled { Text(tab.title).font(.system(size: 12, weight: .medium)) }
                        }
                        .foregroundStyle(.white.opacity(tab == selected ? 0.95 : 0.55))
                    }
                    .buttonStyle(BandButtonStyle())
                    .frame(width: width, height: Self.segmentHeight)
                    .help("\(tab.title) (⌘\((tabs.firstIndex(of: tab) ?? 0) + 1))")
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}
