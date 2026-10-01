#if DEBUG
import AppKit

/// `DEXMA -selftest`: peeks, opens and closes through the view model, printing state, focus
/// and click-through at each step, then checks that settings apply live and opens Settings.
/// Deletes the `panelWidth` and `hotKey` defaults it changed, then quits.
enum SelfTest {
    static func run(coordinator: AppCoordinator, panel: NSPanel, notch: NotchViewModel, session: ShellSession) {
        func report(_ label: String) {
            let responder = panel.firstResponder === session.terminalView ? "terminal" : "\(panel.firstResponder.map { type(of: $0) } as Any)"
            print("[selftest] \(label): state=\(notch.state) progress=\(String(format: "%.3f", notch.progress)) key=\(panel.isKeyWindow) firstResponder=\(responder) appActive=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-") mouseThrough=\(panel.ignoresMouseEvents) terminalHidden=\(session.container.isHidden)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            report("launch")
            notch.setHovering(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                report("peek settled")
                notch.setHovering(false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            report("unpeek settled")
            notch.open()
            report("open requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                report("open settled")
                notch.close()
                report("close requested")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { report("close +150ms") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    report("close settled")
                    settingsChecks(coordinator: coordinator, panel: panel)
                }
            }
        }
    }

    private static func settingsChecks(coordinator: AppCoordinator, panel: NSPanel) {
        let settings = coordinator.settings
        let widthBefore = panel.frame.width
        settings.panelWidth = 800
        print("[selftest] panel width \(widthBefore) → \(panel.frame.width) after settings.panelWidth = 800")
        settings.hotKey = KeyCombo(keyCode: 0x31, carbonModifiers: 0x0800, display: "⌥Space", menuKey: " ")
        settings.hotKey = .defaultCombo
        print("[selftest] hotkey re-registered twice without trouble")
        coordinator.showSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let windows = NSApp.windows.filter(\.isVisible).map { "\($0.title.isEmpty ? String(describing: type(of: $0)) : $0.title) \(Int($0.frame.width))x\(Int($0.frame.height))" }
            print("[selftest] visible windows: \(windows)")
            for key in ["panelWidth", "hotKey"] { UserDefaults.standard.removeObject(forKey: key) }
            NSApp.terminate(nil)
        }
    }
}
#endif
