import AppKit
import WebKit

/// The Search tab's page in the content card: a search field across the top and the web page
/// below it, at the card's fixed size (the content pager clips it to the card's rounded corners
/// and the notch silhouette), so opening, closing and swiping never resize anything.
///
/// The card's background (the page's own colour once known, so the card has no seam), the
/// field's background, its icon and the empty state are drawn in `draw(_:)` (not as layer
/// properties), so `cacheDisplay` pictures them exactly for the motion layer; only the page
/// itself has to come from WebKit (`capture(page:)`).
final class SearchCardView: NSView {
    static let fieldHeight: CGFloat = 30
    static let fieldInset: CGFloat = 10
    /// Until a page reports its background: dark grey, like the system's dark surfaces.
    static let defaultColor = NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)

    let field = NSTextField()
    private(set) var webView: WKWebView
    /// Holds the page. Hidden until the first search: the empty state shows instead.
    private let pageClip = NSView()

    init(size: CGSize, webView: WKWebView) {
        self.webView = webView
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        // Dark controls, caret and page (Google follows prefers-color-scheme) on the black panel.
        appearance = NSAppearance(named: .darkAqua)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = NSColor(white: 0.92, alpha: 1)
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.cell?.sendsActionOnEndEditing = false
        field.placeholderAttributedString = NSAttributedString(
            string: "Search Google or type a URL",
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.38), .font: NSFont.systemFont(ofSize: 13)])
        addSubview(field)

        pageClip.wantsLayer = true
        pageClip.isHidden = true
        pageClip.addSubview(webView)
        addSubview(pageClip)
        layoutCard()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The card's background: the page's own once known.
    var cardColor = SearchCardView.defaultColor {
        didSet { if cardColor != oldValue { needsDisplay = true } }
    }

    /// A page has been loaded: it replaces the empty state (until a reset).
    var showsPage: Bool {
        get { !pageClip.isHidden }
        set {
            guard newValue != showsPage else { return }
            pageClip.isHidden = !newValue
            needsDisplay = true
        }
    }

    /// The page is drawn (not before its first load finished: no white flash).
    var revealsPage: Bool {
        get { webView.alphaValue > 0 }
        set { webView.alphaValue = newValue ? 1 : 0 }
    }

    /// Swaps in another web view (a reset: a fresh one, so the history goes too).
    func replaceWebView(with newView: WKWebView) {
        webView.removeFromSuperview()
        webView = newView
        pageClip.addSubview(newView)
        layoutCard()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCard()
    }

    /// A picture of the card as on screen, with `page` (WebKit's own picture of the web view,
    /// see `SearchSession`) where the page is.
    func capture(page: CGImage?) -> ContentSnapshot? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // With a page, AppKit draws only the field strip above it: drawing the web view would
        // make WebKit render the page synchronously (~20 ms). WebKit's picture goes in instead.
        let pageFrame = pageClip.frame
        let drawn = showsPage
            ? CGRect(x: 0, y: pageFrame.maxY, width: bounds.width, height: bounds.height - pageFrame.maxY)
            : bounds
        guard let rep = bitmapImageRepForCachingDisplay(in: drawn) else { return nil }
        cacheDisplay(in: drawn, to: rep)
        let scale = CGFloat(rep.pixelsWide) / drawn.width
        guard let strip = rep.cgImage else { return nil }
        guard showsPage else { return ContentSnapshot(image: strip, scale: scale) }
        guard let context = CGContext(
            data: nil, width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()),
            bitsPerComponent: 8, bytesPerRow: 0,
            // The page's space: the big page picture goes in unconverted, only the strip is.
            space: page?.colorSpace ?? strip.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // In points and y-up, like this unflipped view.
        context.scaleBy(x: scale, y: scale)
        context.draw(strip, in: drawn)
        context.setFillColor(cardColor.cgColor)
        context.fill(pageFrame)
        if let page, revealsPage { context.draw(page, in: pageFrame) }
        return context.makeImage().map { ContentSnapshot(image: $0, scale: scale) }
    }

    // MARK: Drawing

    private var fieldRect: CGRect {
        let inset = Self.fieldInset
        return CGRect(x: inset, y: bounds.height - inset - Self.fieldHeight,
                      width: max(bounds.width - 2 * inset, 0), height: Self.fieldHeight)
    }

    /// Below the field, edge to edge (the card rounds its bottom corners).
    private var pageRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width,
               height: max(bounds.height - Self.fieldHeight - 2 * Self.fieldInset, 0))
    }

    private func layoutCard() {
        let fieldRect = self.fieldRect
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: fieldRect.minX + 30, y: fieldRect.midY - height / 2,
                             width: max(fieldRect.width - 42, 0), height: height)
        pageClip.frame = pageRect
        // Set outright: autoresizing from the clip's initial zero size would double it.
        webView.frame = pageClip.bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        cardColor.setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.1).setFill()
        NSBezierPath(roundedRect: fieldRect, xRadius: 9, yRadius: 9).fill()
        let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium)
                .applying(.init(paletteColors: [NSColor(white: 1, alpha: 0.5)])))
        if let glass {
            let size = glass.size
            glass.draw(in: CGRect(x: fieldRect.minX + 11, y: fieldRect.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        guard !showsPage else { return }
        let page = pageRect
        drawCentered("Search Google", font: .systemFont(ofSize: 15, weight: .semibold),
                     color: NSColor(white: 1, alpha: 0.55), y: page.midY + 4)
        drawCentered("Type above and press Return  ·  ⌘L focuses the field",
                     font: .systemFont(ofSize: 12), color: NSColor(white: 1, alpha: 0.32), y: page.midY - 20)
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: y))
    }
}
