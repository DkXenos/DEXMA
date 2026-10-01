import AppKit
import SwiftTerm

/// Owns the one long-lived terminal view and the zsh inside it. Created at launch; the shell
/// keeps running while the panel is closed and is respawned whenever it exits.
final class ShellSession: NSObject, LocalProcessTerminalViewDelegate {
    static let shell = "/bin/zsh"

    let container: TerminalContainerView
    var terminalView: LocalProcessTerminalView { container.terminalView }
    /// The shell printed something.
    var onOutput: (() -> Void)?
    private var lastStart = Date.distantPast
    private var cachedSnapshot: TerminalSnapshot?
    private var snapshotScrollPosition: Double = 0

    init(size: CGSize) {
        let terminal = ShellTerminalView(frame: CGRect(origin: .zero, size: size))
        terminal.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        container = TerminalContainerView(terminalView: terminal)
        // Hidden while fully closed so it doesn't draw; the shell keeps running regardless.
        container.isHidden = true
        super.init()
        terminal.processDelegate = self
        terminal.onOutput = { [weak self] in self?.onOutput?() }
        start()
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
