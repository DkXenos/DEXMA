import AppKit

/// The ⌘L "Go to URL" field on the Claude tab: a small text field over the band right of the
/// notch, for pasting a link (say, the sign-in link from an email) into the current tab. An
/// AppKit field above the SwiftUI band (a text field can't live inside its liquid shader).
/// Return goes there, Esc puts it away.
final class URLEntryField: NSTextField, NSTextFieldDelegate {
    /// The text the user submitted.
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 12)
        textColor = NSColor(white: 0.92, alpha: 1)
        cell?.isScrollable = true
        cell?.wraps = false
        cell?.usesSingleLineMode = true
        placeholderAttributedString = NSAttributedString(
            string: "Paste a link and press Return",
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.38), .font: NSFont.systemFont(ofSize: 12)])
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        delegate = self
        target = self
        action = #selector(submit)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shown at `frame` (in the panel's flipped content view), empty and focused.
    func show(at frame: CGRect) {
        self.frame = frame
        stringValue = ""
        isHidden = false
        window?.makeFirstResponder(self)
    }

    func hide() {
        isHidden = true
    }

    @objc private func submit() {
        let text = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmit?(text)
    }

    // The text inside sits a little in from the rounded edge.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}
