import AppKit
import Carbon.HIToolbox
import Observation
import os
import SwiftUI
import WebKit

/// Claude in floating glass (preview): a Spotlight-style field ("Ask Claude…") with round buttons
/// (Capture, New chat, Open in browser), and below it, once there's a conversation, a glass card
/// with claude.ai's page in it — the Claude tab's own web view, moved here from the notch, with
/// the same session. Return in the field puts the question (and a capture waiting as the field's
/// chip) into claude.ai's message box and sends it; claude.ai's own box is hidden meanwhile, and
/// comes back with the text in it if that ever fails, so nothing typed is lost.
/// Selecting the Claude tab in the notch (`ClaudeTabRedirect`), its own shortcut, or Draw to ask
/// (`CaptureHandoffTarget`: the picture lands in the chip) bring it up.
@Observable
final class ClaudeGlassViewModel: ClaudeTabRedirect, CaptureHandoffTarget {
    private static let logger = Logger(category: "Glass")
    /// Capture, New chat, Open in browser.
    static let buttonCount = 3

    /// The card with the conversation is open.
    private(set) var isExpanded = false
    /// A capture waiting for the question (the field's chip).
    private(set) var attachment: CapturedImage?
    /// The question is on its way into claude.ai.
    private(set) var isSending = false
    private(set) var mode: GlassInputMode = .ask
    /// The field's text height (its lines).
    private(set) var inputHeight = GlassTextView.lineHeight
    /// Shortcuts as shown in the buttons' tooltips.
    var captureShortcut = ""

    let glass: FloatingGlassController
    let claude: WebTabViewModel
    let textView = GlassTextView()
    let webCard = GlassWebCard(frame: .zero)

    /// Draw to ask: the Capture button starts it.
    @ObservationIgnored weak var capture: CaptureViewModel?
    /// The notch: steps aside while a capture is drawn, as it does without the glass.
    @ObservationIgnored weak var companion: CaptureHandoffTarget?
    /// About to come up (the notch closes if it's open).
    @ObservationIgnored var onWillPresent: (() -> Void)?
    @ObservationIgnored private(set) var isEnabled = false
    @ObservationIgnored private var seeThrough = true
    /// claude.ai's own composer is hidden (the native field drives it).
    @ObservationIgnored private var nativeComposer = true
    @ObservationIgnored private let composer: ClaudeComposer
    @ObservationIgnored private var captureScreen: NSScreen?
    @ObservationIgnored private var askDraft = ""
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    init(claude: WebTabViewModel) {
        self.claude = claude
        glass = FloatingGlassController(buttonCount: Self.buttonCount)
        composer = ClaudeComposer(tab: claude.session)
        textView.placeholder = mode.placeholder
        textView.onSubmit = { [weak self] in self?.submit() }
        textView.onChange = { [weak self] in self?.textDidChange() }
        let panel = glass.panel
        panel.onEscape = { [weak self] in self?.handleEscape() ?? false }
        panel.onKeyEquivalent = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        // claude.ai's sign-in popup (a window with the page's own web view) keeps it up.
        glass.keepsShownWhenKey = { window in window.contentView is WKWebView }
        claude.onURLChange = { [weak self] url in self?.pageDidChange(url) }
        glass.onDidDismiss = { [weak self] in self?.didDismiss() }
    }

    /// The panel's content: `root` (the SwiftUI glass) with the web card above it.
    func install<Root: View>(root: Root) {
        let content = FloatingGlassContentView(root: root)
        content.addOverlay(webCard)
        glass.panel.contentView = content
        updateWebCardFrame()
    }

    // MARK: Settings

    /// Claude moves into the glass (`enabled`) or back to the notch. The caller hands the card
    /// over: the notch lets go of it first, takes it back after.
    func setEnabled(_ enabled: Bool, seeThrough clear: Bool) {
        let changed = enabled != isEnabled || clear != seeThrough
        seeThrough = clear
        guard changed else { return }
        let session = claude.session
        if enabled {
            if !isEnabled { webCard.adopt(session.card) }
            isEnabled = true
            session.setPresentation(glass: true, clear: clear)
            webCard.dimAmount = clear ? 0.12 : 0
            applyPageStyle()
            updateWebCardFrame()
        } else {
            dismiss(returnsFocus: true)
            isEnabled = false
            webCard.release()
            session.setPresentation(glass: false, clear: false)
            session.pageScript = nil
            composer.apply(clear: false, native: false)
        }
    }

    private func applyPageStyle() {
        claude.session.pageScript = ClaudeComposer.pageScript(clear: seeThrough, native: nativeComposer)
        composer.apply(clear: seeThrough, native: nativeComposer)
    }

    // MARK: Presenting

    var isPresented: Bool { glass.isPresented }

    func toggle() {
        if glass.isPresented { dismiss() } else { present() }
    }

    /// Up on `screen` (default: the pointer's), the field with the keyboard. Open with the card if
    /// claude.ai shows a conversation (or needs signing in).
    func present(on screen: NSScreen? = nil, compact: Bool = false) {
        guard isEnabled else { return }
        let appearing = !glass.isPresented
        if appearing {
            onWillPresent?()
            if !nativeComposer {
                nativeComposer = true  // Try the native field again.
                applyPageStyle()
            }
            isExpanded = !compact && ClaudePageKind(url: claude.url).showsPage
        }
        glass.present(on: screen) { [weak self] in self?.focusField() }
        updateWebCardFrame()
        if appearing, isExpanded { webCard.setShown(true, duration: 0.2, delay: glass.reduceMotion ? 0 : 0.2) }
    }

    func dismiss(returnsFocus: Bool = true) {
        guard glass.isPresented else { return }
        if mode == .link { setMode(.ask) }
        webCard.setShown(false, duration: glass.reduceMotion ? 0.1 : 0.12)
        glass.dismiss(returnsFocus: returnsFocus)
    }

    /// Ordered out: the page stops drawing.
    private func didDismiss() {
        webCard.hideWhenFaded()
    }

    private func focusField() {
        textView.focus()
    }

    // MARK: Card

    /// The capsule's height: one line is Spotlight's 56 pt; it grows with more lines.
    var fieldHeight: CGFloat {
        GlassMetrics.fieldHeight + inputHeight - GlassTextView.lineHeight
    }

    /// The card's spring (morphing out of the field and back).
    private var cardAnimation: Animation {
        glass.reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: 0.38, bounce: 0.12)
    }

    func expand() {
        guard glass.isPresented, !isExpanded else { return }
        withAnimation(cardAnimation) { isExpanded = true }
        updateWebCardFrame()
        webCard.setShown(true, duration: 0.2, delay: glass.reduceMotion ? 0 : 0.22)
    }

    func collapse() {
        guard isExpanded else { return }
        webCard.setShown(false, duration: 0.12) { [weak self] in
            guard let self else { return }
            withAnimation(self.cardAnimation, completionCriteria: .removed) {
                self.isExpanded = false
            } completion: { [weak self] in
                self?.webCard.hideWhenFaded()
            }
        }
    }

    private func updateWebCardFrame() {
        let frame = glass.layout.card(fieldHeight: fieldHeight)
        if webCard.frame != frame { webCard.frame = frame }
    }

    /// A conversation (or the sign-in page) opened in the card's page: the card opens for it.
    private func pageDidChange(_ url: URL?) {
        guard isEnabled, glass.isPresented, ClaudePageKind(url: url).showsPage else { return }
        expand()
    }

    // MARK: Field

    private func textDidChange() {
        let height = textView.fittingHeight
        guard height != inputHeight else { return }
        withAnimation(.smooth(duration: 0.15)) { inputHeight = height }
        updateWebCardFrame()
    }

    private func setMode(_ newMode: GlassInputMode) {
        guard newMode != mode else { return }
        if newMode == .link { askDraft = textView.string }
        mode = newMode
        textView.placeholder = newMode.placeholder
        textView.string = newMode == .ask ? askDraft : ""
        textDidChange()
        focusField()
    }

    func submit() {
        switch mode {
        case .ask: send()
        case .link: openLink()
        }
    }

    /// ⌘L's field: a link opens in the card (claude.ai's sign-in links; anything else goes to
    /// the browser by the tab's own rules).
    private func openLink() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            NSSound.beep()
            return
        }
        claude.session.load(url)
        askDraft = ""
        setMode(.ask)
        expand()
    }

    func removeAttachment() {
        withAnimation(glass.spring) { attachment = nil }
    }

    // MARK: Sending

    /// The question (and the chip's picture) into claude.ai and sent; the card opens to show the
    /// answer. The field keeps the text until it's really sent.
    private func send() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !isSending, !text.isEmpty || attachment != nil else { return }
        isSending = true
        expand()
        let image = attachment
        sendTask = Task { [weak self] in await self?.performSend(text: text, image: image) }
    }

    private func performSend(text: String, image: CapturedImage?) async {
        defer { isSending = false }
        guard await waitForComposer(seconds: 15) else {
            Self.logger.notice("claude.ai's message box isn't there: showing claude.ai's own")
            await fallBack(text: text)
            return
        }
        if let image {
            guard glass.panel.isKeyWindow, await composer.attacher.insert(image, in: glass.panel) != nil else {
                await fallBack(text: text)
                return
            }
            withAnimation(glass.spring) { attachment = nil }
        }
        let result = await composer.send(text)
        guard result == .sent else {
            Self.logger.error("Sending from the glass field failed: \(String(describing: result), privacy: .public)")
            await fallBack(text: text)
            return
        }
        textView.string = ""
        textDidChange()
        if glass.isPresented { textView.focus() }
    }

    private func waitForComposer(seconds: Double) async -> Bool {
        let deadline = CACurrentMediaTime() + seconds
        while CACurrentMediaTime() < deadline {
            switch await composer.attacher.composerState() {
            case .ready: return true
            case .signedOut: return false
            case .loading: try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    /// The native path didn't work (signed out, the page changed): claude.ai's own message box
    /// comes back, with the keyboard and the text in it. The field keeps its text too.
    private func fallBack(text: String) async {
        nativeComposer = false
        applyPageStyle()
        expand()
        try? await Task.sleep(for: .milliseconds(150))  // The box is laid out where it belongs.
        if !text.isEmpty, await composer.attacher.composerState() == .ready {
            _ = await composer.insert(text)
        }
        guard glass.isPresented else { return }
        glass.panel.makeFirstResponder(claude.session.webView)
        claude.session.focusComposer()
    }

    // MARK: Buttons

    func newChat() {
        claude.newChat()
        collapse()
        if glass.isPresented { focusField() }
    }

    func openInBrowser() {
        guard claude.openInBrowser() else { return }
        dismiss(returnsFocus: false)
    }

    func startCapture() {
        capture?.start()
    }

    // MARK: Keys

    private func handleEscape() -> Bool {
        if mode == .link {
            setMode(.ask)
        } else {
            dismiss()
        }
        return true
    }

    /// ⌘↓ / ⌘↑ open and close the card, ⌘⇧R a new chat, ⌘⇧O the browser, ⌘L a link, ⌘R reload,
    /// ⌘[ ⌘] back and forward, ⌘W hides.
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
            switch Int(event.keyCode) {
            case kVK_DownArrow where !flags.contains(.shift):
                expand()
                return true
            case kVK_UpArrow where !flags.contains(.shift):
                collapse()
                return true
            default: break
            }
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command, .shift] {
            switch key {
            case "r": newChat()
            case "o": openInBrowser()
            default: return false
            }
            return true
        }
        guard flags == .command else { return false }
        switch key {
        case "l": setMode(mode == .link ? .ask : .link)
        case "r": claude.reloadOrStop()
        case "[": claude.goBack()
        case "]": claude.goForward()
        case "w": dismiss()
        default: return false
        }
        return true
    }

    // MARK: ClaudeTabRedirect

    func presentClaude() {
        present()
    }

    // MARK: CaptureHandoffTarget

    func captureWillBegin() {
        companion?.captureWillBegin()
        // The overlay takes the keyboard; it hands it back itself if the capture is cancelled.
        dismiss(returnsFocus: false)
    }

    func captureDidEnd() {
        companion?.captureDidEnd()
    }

    func captureLanding(onScreen screenFrame: CGRect) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) else { return nil }
        captureScreen = screen
        let layout = glass.layout(on: screen)
        return layout.onScreen(layout.chip)
    }

    var captureLandingStyle: CaptureLandingStyle { .chip(cornerRadius: GlassMetrics.chipRadius) }

    func prepareForCaptureLanding() {}

    func takeCapture(_ image: CapturedImage) -> Bool {
        attachment = image
        if mode == .link { setMode(.ask) }
        return true
    }

    /// The picture reached the chip: up in the compact state, the field ready for the question.
    func openForCapture() {
        present(on: captureScreen, compact: true)
        captureScreen = nil
    }

    func showClaudeTab() {
        present()
    }

    var isClaudeReadyForInsert: Bool { false }
    func claudeContentDidChange() {}
    func captureChipDidChange() {}

    #if DEBUG
    var debugComposer: ClaudeComposer { composer }
    var debugIsNativeComposer: Bool { nativeComposer }
    func debugSetAttachment(_ image: CapturedImage?) { attachment = image }
    #endif
}
