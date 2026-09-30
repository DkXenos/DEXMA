import AppKit
import SwiftTerm
import SwiftUI

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

/// The terminal view, reporting whenever the shell prints (output arrives on the main queue).
final class ShellTerminalView: LocalProcessTerminalView {
    var onOutput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }
}

/// Holds the terminal at a fixed size and clips it to the notch silhouette with a layer mask,
/// so opening and closing never resizes or re-lays-out the terminal.
final class TerminalContainerView: NSView {
    let terminalView: LocalProcessTerminalView
    private let maskLayer = CAShapeLayer()

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: terminalView.frame)
        wantsLayer = true
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
        layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clips to `shape`, which is laid out in panel coordinates (top-left origin); this view's
    /// top-left corner sits at `origin` in those coordinates.
    /// Called from SwiftUI's update pass, so it only touches layers: changing NSView
    /// properties (isHidden, alphaValue) here makes SwiftUI re-enter layout.
    func update(mask shape: NotchShape, panelSize: CGSize, origin: CGPoint, opacity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        // Panel coordinates are y-down; this (unflipped) view's layer is y-up.
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                          tx: -origin.x, ty: bounds.height + origin.y)
        let path = shape.path(in: CGRect(origin: .zero, size: panelSize)).cgPath
        maskLayer.path = path.copy(using: &transform)
        // The mask's opacity scales the content's alpha: that's the fade.
        maskLayer.opacity = Float(opacity)
        CATransaction.commit()
    }
}
