import AppKit

/// A tab's page in the card while the tab lives elsewhere (Claude in floating glass): what a
/// swipe passes over before the notch hands over. Drawn in `draw(_:)`, like the web tabs' empty
/// state, so the motion layer can picture it.
final class RedirectedTabPage: NSView {
    private let title: String
    private let detail: String

    init(title: String, detail: String) {
        self.title = title
        self.detail = detail
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        WebTabView.defaultColor.setFill()
        bounds.fill()
        drawCentered(title, font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor(white: 1, alpha: 0.55),
                     y: bounds.midY + 4)
        drawCentered(detail, font: .systemFont(ofSize: 12), color: NSColor(white: 1, alpha: 0.32), y: bounds.midY - 20)
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        string.draw(at: CGPoint(x: (bounds.width - string.size().width) / 2, y: y))
    }
}
