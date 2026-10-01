#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only visual check: `DEXMA -snapshot <dir>` renders the panel at a few progress
/// values into PNGs, then quits. An app may render its own windows without Screen Recording
/// permission, so this works from the command line.
enum DebugSnapshot {
    static func runIfRequested(panel: NSPanel, controller: PanelController, session: ShellSession) {
        let arguments = ProcessInfo.processInfo.arguments
        setvbuf(stdout, nil, _IOLBF, 0)  // Line-buffered, so a killed test run keeps its output.
        if arguments.contains("-selftest") {
            selfTest(panel: panel, controller: controller, session: session)
            return
        }
        if let index = arguments.firstIndex(of: "-warptest"), index + 1 < arguments.count {
            WarpTest.run(panel: panel, controller: controller, dir: URL(fileURLWithPath: arguments[index + 1]))
            return
        }
        if let index = arguments.firstIndex(of: "-effecttest"), index + 1 < arguments.count {
            EffectTest.run(panel: panel, controller: controller, session: session,
                           dir: URL(fileURLWithPath: arguments[index + 1]))
            return
        }
        guard let index = arguments.firstIndex(of: "-snapshot"), index + 1 < arguments.count else {
            return
        }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        session.terminalView.process.send(data: ArraySlice(Array("clear; echo DEXMA; ls /\r".utf8)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for progress in [0, 0.15, 0.5, 1] as [CGFloat] {
                controller.debugJump(to: progress)
                write(panel: panel, to: directory.appendingPathComponent("progress-\(progress).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// `DEXMA -selftest`: opens and closes via the controller and prints focus state.
    private static func selfTest(panel: NSPanel, controller: PanelController, session: ShellSession) {
        func report(_ label: String) {
            let responder = panel.firstResponder === session.terminalView ? "terminal" : "\(panel.firstResponder.map { type(of: $0) } as Any)"
            print("[selftest] \(label): state=\(controller.state) progress=\(String(format: "%.3f", controller.progress)) key=\(panel.isKeyWindow) firstResponder=\(responder) appActive=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-") mouseThrough=\(panel.ignoresMouseEvents) terminalHidden=\(session.container.isHidden)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            report("launch")
            controller.setHovering(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                report("peek settled")
                controller.setHovering(false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            report("unpeek settled")
            controller.open()
            report("open requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                report("open settled")
                controller.close()
                report("close requested")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { report("close +150ms") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    report("close settled")
                    settingsChecks(panel: panel)
                }
            }
        }
    }

    private static func settingsChecks(panel: NSPanel) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let widthBefore = panel.frame.width
        app.settings.panelWidth = 800
        print("[selftest] panel width \(widthBefore) → \(panel.frame.width) after settings.panelWidth = 800")
        app.settings.hotKey = KeyCombo(keyCode: 0x31, carbonModifiers: 0x0800, display: "⌥Space", menuKey: " ")
        app.settings.hotKey = .defaultCombo
        print("[selftest] hotkey re-registered twice without trouble")
        app.showSettings(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let windows = NSApp.windows.filter(\.isVisible).map { "\($0.title.isEmpty ? String(describing: type(of: $0)) : $0.title) \(Int($0.frame.width))x\(Int($0.frame.height))" }
            print("[selftest] visible windows: \(windows)")
            for key in ["panelWidth", "hotKey"] { UserDefaults.standard.removeObject(forKey: key) }
            NSApp.terminate(nil)
        }
    }

    private static func write(panel: NSPanel, to url: URL) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
