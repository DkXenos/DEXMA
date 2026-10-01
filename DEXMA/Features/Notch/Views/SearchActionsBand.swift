import SwiftUI

/// The Search tab's buttons right of the notch: back, forward, reload (stop while loading)
/// and open in the default browser.
struct SearchActionsBand: View {
    static let buttonSize = CGSize(width: 28, height: 24)

    let search: SearchViewModel
    let size: CGSize

    var body: some View {
        HStack(spacing: 2) {
            button("chevron.left", help: "Back (⌘[)", enabled: search.canGoBack, action: search.goBack)
            button("chevron.right", help: "Forward (⌘])", enabled: search.canGoForward,
                   action: search.goForward)
            button(search.isLoading ? "xmark" : "arrow.clockwise",
                   help: search.isLoading ? "Stop" : "Reload (⌘R)", enabled: search.hasPage,
                   action: search.reloadOrStop)
            button("safari", help: "Open in Browser", enabled: search.hasPage, action: search.openInBrowser)
        }
        .frame(width: size.width, height: size.height, alignment: .trailing)
    }

    private func button(_ symbol: String, help: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(BandButtonStyle())
        .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
        .disabled(!enabled)
        .help(help)
    }
}
