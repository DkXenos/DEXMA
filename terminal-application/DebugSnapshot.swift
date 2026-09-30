#if DEBUG
import AppKit
import SwiftTerm

/// Debug-only visual check: `NotchTerm -snapshot <dir>` renders the panel at a few progress
/// values into PNGs, then quits. An app may render its own windows without Screen Recording
/// permission, so this works from the command line.
enum DebugSnapshot {
    static func runIfRequested(panel: NSPanel, controller: PanelController, session: ShellSession) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-selftest") {
            selfTest(panel: panel, controller: controller, session: session)
            return
        }
        guard let index = arguments.firstIndex(of: "-snapshot"), index + 1 < arguments.count else {
            return
        }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        session.terminalView.process.send(data: ArraySlice(Array("clear; echo NotchTerm; ls /\r".utf8)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for progress in [0, 0.15, 0.5, 1] as [CGFloat] {
                controller.debugJump(to: progress)
                write(panel: panel, to: directory.appendingPathComponent("progress-\(progress).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// `NotchTerm -selftest`: opens and closes via the controller and prints focus state.
    private static func selfTest(panel: NSPanel, controller: PanelController, session: ShellSession) {
        func report(_ label: String) {
            let responder = panel.firstResponder === session.terminalView ? "terminal" : "\(panel.firstResponder.map { type(of: $0) } as Any)"
            print("[selftest] \(label): state=\(controller.state) progress=\(String(format: "%.3f", controller.progress)) key=\(panel.isKeyWindow) firstResponder=\(responder) appActive=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-") mouseThrough=\(panel.ignoresMouseEvents) terminalHidden=\(session.container.isHidden)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            report("launch")
            controller.open()
            report("open requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                report("open settled")
                controller.close()
                report("close requested")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { report("close +150ms") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    report("close settled")
                    NSApp.terminate(nil)
                }
            }
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
