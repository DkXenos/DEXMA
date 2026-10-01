import SwiftUI

/// Right of the notch: the selected tab's context, crossfading with the tab progress (each
/// tab's context is fully there on its tab, gone a page away). Terminal: the working directory
/// (and the running dot, see `RunningDotView`); Search: lock, domain, Reset, Open in browser.
/// Only the selected tab's buttons take clicks.
struct BandContext: View {
    let viewModel: NotchViewModel

    var body: some View {
        let region = viewModel.geometry.actionBandFrame
        let progress = viewModel.tabProgress
        ZStack(alignment: .topLeading) {
            TerminalContext(layout: viewModel.terminalContext,
                            showsDot: viewModel.showsStaticRunningDot)
                .opacity(reveal(.terminal, progress))
            SearchContext(search: viewModel.search, band: viewModel.band, region: region,
                          click: { viewModel.click($0) })
                .opacity(reveal(.search, progress))
                .allowsHitTesting(viewModel.tab == .search)
        }
    }

    private func reveal(_ tab: PanelTab, _ progress: CGFloat) -> CGFloat {
        let index = CGFloat(PanelTab.allCases.firstIndex(of: tab) ?? 0)
        return max(0, 1 - abs(progress - index))
    }
}

/// The working directory, laid out by `TerminalContextLayout` (panel coordinates). The pulsing
/// running dot is an AppKit overlay at rest; while the panel moves this draws it (still), so
/// the liquid effect bends it with the rest of the band.
private struct TerminalContext: View {
    let layout: TerminalContextLayout
    let showsDot: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsDot {
                Circle()
                    .fill(Color(nsColor: RunningDotView.color))
                    .frame(width: layout.dotFrame.width, height: layout.dotFrame.height)
                    .offset(x: layout.dotFrame.minX, y: layout.dotFrame.minY)
            }
            Text(layout.text)
                .font(.system(size: TerminalContextLayout.fontSize, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
                .frame(width: layout.textFrame.width, height: layout.textFrame.height, alignment: .trailing)
                .offset(x: layout.textFrame.minX, y: layout.textFrame.minY)
        }
    }
}

/// Lock (over HTTPS) and domain, then Reset and Open in browser, right-aligned in the region.
private struct SearchContext: View {
    static let buttonSize = CGSize(width: 32, height: 28)

    let search: SearchViewModel
    let band: BandMotion
    let region: CGRect
    let click: (@escaping () -> Void) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: TerminalContextLayout.notchMargin)
            if search.isSecure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.trailing, 4)
            }
            Text(search.domain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.trailing, 6)
            button("search.reset", "arrow.counterclockwise", help: "Reset", enabled: search.hasPage,
                   action: search.reset)
            button("search.open", "safari", help: "Open in Browser", enabled: search.hasPage,
                   action: search.openInBrowser)
        }
        .frame(width: region.width, height: region.height, alignment: .trailing)
        .offset(x: region.minX, y: region.minY)
    }

    private func button(_ id: String, _ symbol: String, help: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button { click(action) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(BandButtonStyle(lens: band.lens(for: id), size: Self.buttonSize))
        .disabled(!enabled)
        .help(help)
    }
}
