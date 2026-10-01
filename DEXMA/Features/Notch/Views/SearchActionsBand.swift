import SwiftUI

/// The Search tab's buttons right of the notch: back, forward, reload (stop while loading)
/// and open in the default browser.
struct SearchActionsBand: View {
    static let buttonSize = CGSize(width: 28, height: 24)

    let search: SearchViewModel
    let band: BandMotion
    let size: CGSize
    /// Runs a button's action (with the click's haptic tick).
    let click: (@escaping () -> Void) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("back", "chevron.left", help: "Back (⌘[)", enabled: search.canGoBack, action: search.goBack)
            button("forward", "chevron.right", help: "Forward (⌘])", enabled: search.canGoForward,
                   action: search.goForward)
            button("reload", search.isLoading ? "xmark" : "arrow.clockwise",
                   help: search.isLoading ? "Stop" : "Reload (⌘R)", enabled: search.hasPage,
                   action: search.reloadOrStop)
            button("open", "safari", help: "Open in Browser", enabled: search.hasPage, action: search.openInBrowser)
        }
        .frame(width: size.width, height: size.height, alignment: .trailing)
    }

    private func button(_ id: String, _ symbol: String, help: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button { click(action) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(BandButtonStyle(lens: band.lens(for: "search.\(id)"), size: Self.buttonSize))
        .disabled(!enabled)
        .help(help)
    }
}
