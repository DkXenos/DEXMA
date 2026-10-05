import AppKit

/// The floating glass's question field: a native AppKit text view in Spotlight's type (SF Pro 26),
/// in the system's label colours (they follow light/dark over the glass). Return sends, ⇧Return
/// starts a new line (as in claude.ai's own box); it grows to `GlassMetrics.maxLines` lines, then
/// scrolls. Made once and kept: the glass's views take it in and out without recreating it.
final class GlassTextView: NSTextView {
    static let font = NSFont.systemFont(ofSize: GlassMetrics.fontSize)
    /// One line's height in this font (the layout manager's, so the field's height matches it).
    static let lineHeight: CGFloat = NSLayoutManager().defaultLineHeight(for: font)

    var placeholder = "" {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }
    var onSubmit: (() -> Void)?
    /// The text changed (and with it maybe the number of lines).
    var onChange: (() -> Void)?

    /// The scroll view it lives in (no scroller shown: it only scrolls past the last line).
    let scrollView = NSScrollView()

    init() {
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: Self.lineHeight), textContainer: container)
        font = Self.font
        textColor = .labelColor
        insertionPointColor = .labelColor
        typingAttributes = [.font: Self.font, .foregroundColor: NSColor.labelColor]
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = CGSize(width: 0, height: Self.lineHeight)
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        focusRingType = .none
        setAccessibilityLabel("Ask Claude")

        scrollView.documentView = self
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The text's height, at most `maxLines` lines (then it scrolls).
    var fittingHeight: CGFloat {
        guard let layoutManager, let textContainer else { return Self.lineHeight }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        let lines = max(1, min((used / Self.lineHeight).rounded(), CGFloat(GlassMetrics.maxLines)))
        return lines * Self.lineHeight
    }

    /// Take the keyboard as soon as it's in a window (SwiftUI puts the field in a moment after
    /// the glass is told to show it).
    var takesFocusWhenShown = false

    /// Makes it the first responder now, or as soon as it's in a window.
    func focus() {
        if let window {
            window.makeFirstResponder(self)
            selectAll(nil)  // Like Spotlight: typing replaces what's left from last time.
        } else {
            takesFocusWhenShown = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusWhenShown, let window else { return }
        takesFocusWhenShown = false
        window.makeFirstResponder(self)
        selectAll(nil)
    }

    // MARK: Keys

    /// ⇧ was held for the key being handled (read from the key event itself).
    private var shiftHeld = false

    override func keyDown(with event: NSEvent) {
        shiftHeld = event.modifierFlags.contains(.shift)
        super.keyDown(with: event)
        shiftHeld = false
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            if shiftHeld {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.doCommand(by: selector)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true  // The placeholder.
        onChange?()
    }

    /// Plain text only: a paste of styled text keeps just its characters, in the field's type.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.placeholderTextColor]
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: .zero)
    }
}
