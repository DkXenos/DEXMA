import AppKit
import Observation
import os

/// Draw to ask: freezes the display under the pointer, lets the user draw around something,
/// crops that from the frozen picture, flies it into the notch, opens the Claude tab and puts the
/// picture in claude.ai's message box with the caret there, ready for the question. Started by
/// the band's Capture button, its own global shortcut or the menu bar item.
///
/// If the message box isn't there yet (loading, signed out) the capture waits as a chip in the
/// band and goes in as soon as it is (for a minute; then a click on the chip tries again).
/// Captures stay in memory; nothing touches the disk unless "save copies" is on.
@Observable
final class CaptureViewModel {
    private static let logger = Logger(category: "Capture")
    /// How long a capture waits for claude.ai's message box by itself.
    static let insertTimeout: Double = 60

    private(set) var phase: CapturePhase = .idle
    /// A capture waiting for claude.ai's message box: the band's chip.
    private(set) var pending: PendingCapture? {
        didSet { if (oldValue == nil) != (pending == nil) { target?.captureChipDidChange() } }
    }
    /// The capture shortcut as shown, e.g. "⌥⇧`" (the Capture button's tooltip).
    var shortcut = ""
    /// How the last capture went into claude.ai (for the log and the debug harness).
    @ObservationIgnored private(set) var lastMethod: ClaudeInsertMethod?

    @ObservationIgnored weak var target: CaptureHandoffTarget?
    @ObservationIgnored var startsNewChat = false
    @ObservationIgnored var savesCopies = false
    /// The edge glow and stroke shimmer, 0 … 1 (follows the glass strength unless set apart).
    @ObservationIgnored var effectIntensity: CGFloat = 1

    @ObservationIgnored private weak var router: (any WindowRouter)?
    @ObservationIgnored private let panel: CaptureOverlayPanel
    @ObservationIgnored private let claude: WebTab
    @ObservationIgnored private let attacher: ClaudeAttacher
    @ObservationIgnored private var screen: NSScreen?
    @ObservationIgnored private var frozen: FrozenScreen?
    /// A stroke that ended before the frozen picture arrived.
    @ObservationIgnored private var waitingStroke: [CGPoint]?
    @ObservationIgnored private var look = CaptureLook.full
    @ObservationIgnored private var animated = true
    /// Each capture's number: callbacks of a cancelled one see a newer number and do nothing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var leaving = false
    /// Screen Recording was seen granted (asking costs ~10 ms, so it's asked off the main thread
    /// and only until it's yes).
    @ObservationIgnored private var permitted = false
    @ObservationIgnored private var insertTask: Task<Void, Never>?
    @ObservationIgnored private var spaceObserver: NSObjectProtocol?

    init(panel: CaptureOverlayPanel, claude: WebTab, router: any WindowRouter) {
        self.panel = panel
        self.claude = claude
        self.router = router
        attacher = ClaudeAttacher(tab: claude)
        panel.onEscape = { [weak self] in self?.cancel() }
        panel.overlay.onStrokeBegan = { [weak self] in
            if self?.phase == .freezing || self?.phase == .drawing { self?.phase = .drawing }
        }
        panel.overlay.onStrokeEnded = { [weak self] points in self?.strokeEnded(points) }
        // Switching Spaces mid-capture: the frozen picture is of the old one.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelDrawing() }
        }
    }

    var isActive: Bool { phase != .idle }

    // MARK: Start / cancel

    /// The shortcut: starts capture, or cancels the one going on.
    func toggle() {
        if isActive { cancel() } else { start() }
    }

    /// Starts capture on the display under the pointer; without Screen Recording, explains why
    /// it's needed instead.
    func start() {
        guard !isActive else { return }
        Task {
            if !permitted {
                permitted = await Task.detached(priority: .userInitiated) { CGPreflightScreenCaptureAccess() }.value
            }
            guard permitted else {
                router?.showCaptureOnboarding()
                return
            }
            let pointer = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                    ?? NSScreen.screens.first else { return }
            begin(on: screen, freeze: ScreenFreezer.freeze)
        }
    }

    /// Esc, the shortcut again, or a Space switch: everything fades and nothing else happens.
    /// Not once the notch has started opening (the picture is in it by then).
    func cancel() {
        guard isActive, !leaving else { return }
        generation += 1
        let id = generation
        leaving = true
        panel.overlay.fadeAway(duration: animated ? look.fadeOut : look.reducedFade) { [weak self] in
            guard let self, id == self.generation else { return }
            self.closeOverlay(handedOff: false)
        }
    }

    /// Displays changed or the Space switched: a capture still being drawn is cancelled.
    func cancelDrawing() {
        guard phase == .freezing || phase == .drawing else { return }
        cancel()
    }

    /// Capture mode on `screen`: the overlay comes up at once (glow and hint), the frozen picture
    /// (`freeze`) a moment later. Strokes are taken from the start.
    private func begin(on screen: NSScreen, freeze: @escaping (NSScreen) async throws -> FrozenScreen) {
        guard !isActive else { return }
        generation += 1
        let id = generation
        phase = .freezing
        leaving = false
        frozen = nil
        waitingStroke = nil
        self.screen = screen
        target?.captureWillBegin()
        animated = !reduceMotion
        look = CaptureLook.full.scaled(by: effectIntensity)
        panel.setFrame(screen.frame, display: false)
        panel.overlay.prepare(size: screen.frame.size, scale: screen.backingScaleFactor, look: look,
                              animated: animated, hintTop: Self.hintTop(on: screen))
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.overlay.appear()
        Task {
            do {
                let frozen = try await freeze(screen)
                guard id == generation, !leaving else { return }
                self.frozen = frozen
                panel.overlay.showFrozen(frozen.image)
                // Closing the panel hands the keyboard back to the app it came from; make sure
                // that didn't take it from the overlay (Esc must reach it).
                if !panel.isKeyWindow { panel.makeKey() }
                if phase == .freezing { phase = .drawing }
                if let points = waitingStroke {
                    waitingStroke = nil
                    strokeEnded(points)
                }
            } catch {
                Self.logger.error("Freezing the screen failed: \(error.localizedDescription, privacy: .public)")
                guard id == generation else { return }
                cancel()
                permitted = await Task.detached { CGPreflightScreenCaptureAccess() }.value
                // Allowed in System Settings but not taking effect yet: the sheet offers a relaunch.
                router?.showCaptureOnboarding()
            }
        }
    }

    // MARK: Selecting

    private func strokeEnded(_ points: [CGPoint]) {
        guard !leaving, phase == .freezing || phase == .drawing else { return }
        guard let frozen, let screen else {
            waitingStroke = points  // Taken as soon as the frozen picture arrives.
            return
        }
        phase = .selecting
        let bounds = CGRect(origin: .zero, size: frozen.size)
        let click = CaptureSelection.isClick(points)
        let rect = click
            ? CaptureSelection.window(at: points.first ?? .zero, frames: frozen.windows, in: bounds)
            : CaptureSelection.rect(around: points, in: bounds) ?? bounds
        Haptics.tap()
        let id = generation
        // Cropped and encoded off the main thread while the selection settles.
        let encoding = Task.detached(priority: .userInitiated) { CaptureEncoder.encode(frozen, selection: rect) }
        panel.overlay.select(rect, fromStroke: !click) { [weak self] in
            Task {
                let image = await encoding.value
                guard let self, id == self.generation, !self.leaving else { return }
                guard let image else {
                    Self.logger.error("Cropping the capture failed")
                    self.cancel()
                    return
                }
                self.handOff(image, from: screen)
            }
        }
    }

    // MARK: Hand-off

    /// The picture flies into the notch (or, with Reduce Motion, everything fades), the notch opens
    /// on the Claude tab, and the picture goes into the message box once the panel is at rest.
    private func handOff(_ image: CapturedImage, from screen: NSScreen) {
        phase = .flying
        if savesCopies { CaptureArchive.save(image.png) }
        if startsNewChat { claude.goHome() }  // Loads while the notch opens.
        target?.prepareForCaptureLanding()
        let id = generation
        var opened = false
        let open = { [weak self] in
            guard let self, id == self.generation, !self.leaving, !opened else { return }
            opened = true
            self.leaving = true  // Too late to cancel: the picture is in the notch.
            self.target?.openForCapture()
            self.insert(image)
        }
        guard animated else {
            panel.overlay.fadeAway(duration: look.reducedFade) { [weak self] in
                open()
                guard let self, id == self.generation else { return }
                self.closeOverlay(handedOff: opened)
            }
            return
        }
        let landing = target?.captureLanding(onScreen: screen.frame)
        // Into the notch; if the panel opens on another display, up and off this one's top edge.
        let point = landing.map { CGPoint(x: $0.midX - screen.frame.minX, y: screen.frame.maxY - $0.midY) }
            ?? CGPoint(x: screen.frame.width / 2, y: -40)
        panel.overlay.fly(to: point, arriving: open) { [weak self] in
            open()
            guard let self, id == self.generation else { return }
            self.closeOverlay(handedOff: opened)
        }
    }

    /// The overlay leaves the screen and lets go of the frozen picture. Without a hand-off the
    /// keyboard goes back to the app the user was in.
    private func closeOverlay(handedOff: Bool) {
        let wasKey = panel.isKeyWindow
        panel.orderOut(nil)
        panel.overlay.clear()
        frozen = nil
        waitingStroke = nil
        phase = .idle
        leaving = false
        NSCursor.arrow.set()
        if wasKey, !handedOff { NSApp.deactivate() }
        target?.captureDidEnd()
    }

    // MARK: Into claude.ai

    /// Puts `image` in the message box as soon as the Claude tab is open and at rest and the box
    /// is there; meanwhile (after a moment, or right away if the page isn't ready) it waits as
    /// the band's chip. Gives up after `insertTimeout`, keeping the chip to retry.
    private func insert(_ image: CapturedImage) {
        insertTask?.cancel()
        pending = nil
        insertTask = Task { [weak self] in await self?.insertWhenReady(image) }
    }

    private func insertWhenReady(_ image: CapturedImage) async {
        let start = CACurrentMediaTime()
        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - start
            if let target, target.isClaudeReadyForInsert, let window = claude.card.window, window.isKeyWindow {
                let state = await attacher.composerState()
                guard !Task.isCancelled else { return }
                if state == .ready {
                    if let method = await attacher.insert(image, in: window) {
                        lastMethod = method
                        pending = nil
                        target.claudeContentDidChange()
                    } else {
                        pending = PendingCapture(image: image, state: .needsRetry)
                    }
                    return
                }
                if pending == nil { pending = PendingCapture(image: image, state: .waiting) }
            } else if pending == nil, elapsed > 2 {
                pending = PendingCapture(image: image, state: .waiting)
            }
            if elapsed > insertTimeout {
                pending = PendingCapture(image: image, state: .needsRetry)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The chip was clicked: show the Claude tab and try again (another minute).
    func retryPending() {
        guard let pending else { return }
        target?.showClaudeTab()
        self.pending?.state = .waiting
        insertTask?.cancel()
        let image = pending.image
        insertTask = Task { [weak self] in await self?.insertWhenReady(image) }
    }

    /// The chip's ✕: the capture is dropped.
    func discardPending() {
        insertTask?.cancel()
        insertTask = nil
        pending = nil
    }

    // MARK: Helpers

    private var reduceMotion: Bool {
        #if DEBUG
        if let debugReduceMotion { return debugReduceMotion }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var insertTimeout: Double {
        #if DEBUG
        if let debugInsertTimeout { return debugInsertTimeout }
        #endif
        return Self.insertTimeout
    }

    /// Below the menu bar (and the notch), where the hint pill goes.
    private static func hintTop(on screen: NSScreen) -> CGFloat {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return max(screen.safeAreaInsets.top, menuBar, 24) + 14
    }

    #if DEBUG
    @ObservationIgnored var debugReduceMotion: Bool?
    @ObservationIgnored var debugInsertTimeout: Double?
    var debugPanel: CaptureOverlayPanel { panel }
    func debugForgetLastMethod() { lastMethod = nil }
    var debugAttacher: ClaudeAttacher { attacher }

    /// Capture mode on `screen` with `frozen` standing in for ScreenCaptureKit's picture, arriving
    /// after `delay` seconds.
    func debugBegin(on screen: NSScreen, frozen: FrozenScreen, delay: Double) {
        begin(on: screen) { _ in
            try await Task.sleep(for: .seconds(delay))
            return frozen
        }
    }
    #endif
}
