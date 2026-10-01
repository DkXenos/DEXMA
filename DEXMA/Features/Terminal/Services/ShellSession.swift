import AppKit
import Darwin
import SwiftTerm

/// Owns the one long-lived terminal view and the zsh inside it. Created at launch; the shell
/// keeps running while the panel is closed and is respawned whenever it exits.
final class ShellSession: NSObject, LocalProcessTerminalViewDelegate, MotionContent {
    static let shell = "/bin/zsh"

    let container: TerminalContainerView
    var terminalView: LocalProcessTerminalView { container.terminalView }
    /// The shell printed something.
    var onOutput: (() -> Void)?
    /// Working directory and whether a command is running, for the band.
    let status = ShellStatus()
    /// The working directory or the running state changed.
    var onStatusChange: (() -> Void)?
    private var statusRefreshPending = false
    var onSnapshotRefreshed: (() -> Void)?
    private var lastStart = Date.distantPast
    private var cachedSnapshot: TerminalSnapshot?
    private var snapshotScrollPosition: Double = 0

    init(size: CGSize) {
        let terminal = ShellTerminalView(frame: CGRect(origin: .zero, size: size))
        terminal.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        container = TerminalContainerView(size: size, terminalView: terminal)
        // Hidden while fully closed so it doesn't draw; the shell keeps running regardless.
        container.isHidden = true
        super.init()
        terminal.processDelegate = self
        terminal.onOutput = { [weak self] in
            self?.onOutput?()
            self?.scheduleStatusRefresh()
        }
        start()
    }

    // MARK: Status (working directory, running command)

    /// Re-reads the shell's working directory and whether a command runs in the foreground,
    /// straight from the processes: no shell integration needed, so it works with any .zshrc
    /// (an OSC 7 hook would depend on it). A few µs.
    func refreshStatus() {
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return }
        let before = (status.directory, status.isRunningCommand)
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size {
            let directory = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !directory.isEmpty, directory != status.directory { status.directory = directory }
        }
        // The terminal's foreground process group is the shell's own at the prompt, a command's
        // while one runs (zsh gives each job its own group).
        let foreground = tcgetpgrp(terminalView.process.childfd)
        let running = foreground > 0 && foreground != getpgid(pid)
        if running != status.isRunningCommand { status.isRunningCommand = running }
        if before != (status.directory, status.isRunningCommand) { onStatusChange?() }
    }

    /// After output (a prompt, a command starting or finishing), coalesced.
    private func scheduleStatusRefresh() {
        guard !statusRefreshPending else { return }
        statusRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.statusRefreshPending = false
            self?.refreshStatus()
        }
    }

    /// A picture of the terminal as it looks now, for the motion layer. Reuses the last one
    /// unless something changed since: `invalidateSnapshot`, or the view scrolled.
    func snapshot() -> TerminalSnapshot? {
        if cachedSnapshot == nil || terminalView.scrollPosition != snapshotScrollPosition {
            cachedSnapshot = TerminalSnapshot.capture(terminalView)
            snapshotScrollPosition = terminalView.scrollPosition
        }
        return cachedSnapshot
    }

    func invalidateSnapshot() {
        cachedSnapshot = nil
    }

    /// The terminal has scrolled since the cached snapshot was taken.
    var snapshotScrolledAway: Bool {
        cachedSnapshot != nil && terminalView.scrollPosition != snapshotScrollPosition
    }

    /// The cached snapshot has no caret but the live terminal (focused) shows one.
    var snapshotMissesCaret: Bool {
        cachedSnapshot.map { !$0.showsCaret && terminalView.hasFocus } ?? false
    }

    /// Restarts the caret's blink at full opacity, the way snapshots draw it, so the live
    /// caret takes over from a snapshot without a jump. (Re-setting `caretViewTracksFocus`
    /// is SwiftTerm's public way to restart it.)
    func restartCaretBlink() {
        guard terminalView.hasFocus else { return }
        terminalView.caretViewTracksFocus = terminalView.caretViewTracksFocus
    }

    // MARK: MotionContent

    func motionSnapshot() -> ContentSnapshot? {
        guard var content = snapshot()?.content else { return nil }
        content.origin = container.terminalOrigin
        return content
    }

    /// Captured synchronously (a few ms), so it never needs `onSnapshotRefreshed`.
    func refreshSnapshot() {
        _ = snapshot()
    }

    func isChanged(by type: NSEvent.EventType) -> Bool {
        // Scroll events also arrive during a close swipe, with nothing left to scroll:
        // only an actual scroll makes the snapshot stale.
        type != .scrollWheel || snapshotScrolledAway
    }

    func didReappear() -> Bool {
        restartCaretBlink()
        // Taken while closed (no caret): retake it with the caret.
        return snapshotMissesCaret
    }

    func resize(to size: CGSize) {
        guard container.frame.size != size else { return }
        container.setFrameSize(size)
    }

    /// Whether the viewport shows the newest output (nothing further down to scroll to).
    var isScrolledToBottom: Bool {
        !terminalView.canScroll || terminalView.scrollPosition >= 1
    }

    /// Full-screen programs (vim, less, htop) use the alternate screen buffer.
    var isRunningFullScreenProgram: Bool {
        terminalView.getTerminal().isCurrentBufferAlternate
    }

    private func start() {
        lastStart = Date()
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        environment.append("TERM_PROGRAM=DEXMA")
        environment.append("SHELL=\(Self.shell)")
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            environment.append("PATH=\(path)")
        }
        // argv[0] "-zsh" makes it a login shell, so /etc/zprofile sets up PATH as in Terminal.
        terminalView.startProcess(executable: Self.shell, args: [], environment: environment,
                                  execName: "-zsh", currentDirectory: NSHomeDirectory())
    }

    // MARK: LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // A shell that dies right away (e.g. a broken .zshrc) is retried at most once a second.
        let delay = max(0, 1 - Date().timeIntervalSince(lastStart))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.terminalView.feed(text: "\u{1b}c")  // RIS: clear whatever the old shell left.
            self.start()
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
