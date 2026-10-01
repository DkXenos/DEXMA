#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only: `DEXMA -sizetest <dir>` sets the open panel's size from Settings (smallest,
/// default, largest), opens every tab at each and checks that the card, the pages, the web
/// views, the terminal and the band follow; writes a PNG per size and tab, then quits. Removes
/// the size settings it wrote (back to the defaults).
enum SizeTest {
    static func run(coordinator: AppCoordinator, panel: NotchPanel, notch: NotchViewModel,
                    session: ShellSession, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false
            let settings = coordinator.settings
            let sizes: [(String, Double, Double)] = [
                ("smallest", AppSettings.panelWidthRange.lowerBound, AppSettings.panelHeightRange.lowerBound),
                ("default", 680, 400),
                ("largest", AppSettings.panelWidthRange.upperBound, AppSettings.panelHeightRange.upperBound),
            ]
            for (name, width, height) in sizes {
                settings.panelWidth = width
                settings.panelHeight = height
                try? await Task.sleep(for: .milliseconds(300))
                notch.open()
                _ = await notch.waitForRest()
                print("[size]   after open: state \(notch.state) progress \(notch.progress) key \(panel.isKeyWindow)")
                let g = notch.geometry
                let card = g.contentFrame
                for tab in PanelTab.allCases {
                    notch.select(tab)
                    while notch.debugTabDriver.isAnimating { try? await Task.sleep(for: .milliseconds(20)) }
                    try? await Task.sleep(for: .milliseconds(700))
                    print("[size]   \(tab): state \(notch.state) progress \(notch.progress) tabProgress \(notch.tabProgress)")
                    if let image = DebugImages.window(panel) { DebugImages.write(image, dir, "\(name)-\(tab)") }
                }
                let pagesFit = notch.pager.pages.allSatisfy { $0.frame.size == card.size }
                let webFit = [notch.search.session, notch.claude.session].allSatisfy {
                    $0.card.frame.size == card.size && $0.webView.frame.width == card.width
                }
                let terminal = session.terminalView.frame.size
                let terminalFits = abs(terminal.width - (card.width - 18)) < 1 && abs(terminal.height - (card.height - 18)) < 1
                let ok = pagesFit && webFit && terminalFits && notch.pager.frame.size == card.size
                print(String(format: "[size] %@ %@: asked %.0f × %.0f → expanded %.0f × %.0f (panel %.0f × %.0f), card %.0f × %.0f, pages fit %@, web views fit %@, terminal %.0f × %.0f (%d × %d cells)",
                             ok ? "OK  " : "FAIL", name, width, height, g.expandedSize.width, g.expandedSize.height,
                             g.panelFrame.width, g.panelFrame.height, card.width, card.height,
                             pagesFit ? "yes" : "NO", webFit ? "yes" : "NO", terminal.width, terminal.height,
                             session.terminalView.getTerminal().cols, session.terminalView.getTerminal().rows))
                notch.select(.terminal)
                try? await Task.sleep(for: .milliseconds(500))
                notch.close()
                _ = await notch.waitForRest()
            }
            UserDefaults.standard.removeObject(forKey: "panelWidth")
            UserDefaults.standard.removeObject(forKey: "panelHeight")
            NSApp.terminate(nil)
        }
    }
}
#endif
