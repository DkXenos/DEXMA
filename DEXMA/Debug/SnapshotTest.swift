#if DEBUG
import AppKit
import SwiftTerm

/// `DEXMA -snapshot <dir>`: types into the shell, renders the panel at a few progress values
/// into PNGs, then quits. An app may render its own windows without Screen Recording
/// permission, so this works from the command line. Only the shape shows: `debugJump` moves
/// the panel without un-hiding the terminal.
enum SnapshotTest {
    static func run(panel: NSPanel, notch: NotchViewModel, session: ShellSession, dir: URL) {
        session.terminalView.process.send(data: ArraySlice(Array("clear; echo DEXMA; ls /\r".utf8)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for progress in [0, 0.15, 0.5, 1] as [CGFloat] {
                notch.debugJump(to: progress)
                write(panel: panel, to: dir.appendingPathComponent("progress-\(progress).png"))
            }
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
