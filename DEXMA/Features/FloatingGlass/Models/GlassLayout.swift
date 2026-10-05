import CoreGraphics

/// Where the floating glass window and its shapes go on a screen (pure). The field sits where
/// Spotlight's does: centred, its top at `GlassMetrics.fieldTopFraction` of the screen's height.
/// The buttons follow it to the right, the card opens below it (as tall as the screen allows, up
/// to `cardMaxFraction`). The window is fixed per screen, big enough for every state, so nothing
/// resizes it while it animates. Local rects are in the window, top-left origin.
nonisolated struct GlassLayout: Equatable {
    /// The window, in global AppKit coordinates (y up).
    let windowFrame: CGRect
    /// The field at one line.
    let field: CGRect
    let buttons: [CGRect]
    /// The card with the field at one line.
    let card: CGRect

    init(screenFrame: CGRect, visibleFrame: CGRect, buttonCount: Int) {
        let m = GlassMetrics.self
        let fieldTopY = screenFrame.maxY - (screenFrame.height * m.fieldTopFraction).rounded()
        let fieldX = (screenFrame.midX - m.fieldWidth / 2).rounded()
        let cardTopY = fieldTopY - m.fieldHeight - m.cardGap
        let room = cardTopY - (visibleFrame.minY + m.bottomMargin)
        let cardHeight = max(min((screenFrame.height * m.cardMaxFraction).rounded(), room), m.cardMinHeight).rounded()
        let buttonsWidth = CGFloat(buttonCount) * (m.buttonGap + m.buttonSize)
        let minX = fieldX - m.shadowMargin
        let maxY = fieldTopY + m.shadowMargin
        let minY = cardTopY - cardHeight - m.shadowMargin
        windowFrame = CGRect(x: minX, y: minY, width: m.fieldWidth + buttonsWidth + 2 * m.shadowMargin,
                             height: maxY - minY)
        field = CGRect(x: m.shadowMargin, y: m.shadowMargin, width: m.fieldWidth, height: m.fieldHeight)
        let field = self.field
        buttons = (0..<buttonCount).map { index in
            CGRect(x: field.maxX + m.buttonGap + CGFloat(index) * (m.buttonSize + m.buttonGap),
                   y: field.midY - m.buttonSize / 2, width: m.buttonSize, height: m.buttonSize)
        }
        card = CGRect(x: field.minX, y: field.maxY + m.cardGap, width: m.fieldWidth, height: cardHeight)
    }

    /// The card under a field `fieldHeight` tall (grown by extra lines): it starts lower and
    /// keeps its bottom edge.
    func card(fieldHeight: CGFloat) -> CGRect {
        let extra = max(fieldHeight - field.height, 0)
        return CGRect(x: card.minX, y: card.minY + extra, width: card.width,
                      height: max(card.height - extra, GlassMetrics.cardMinHeight / 2))
    }

    /// A capture's chip: at the field's left, centred on its first line.
    var chip: CGRect {
        let size = GlassMetrics.chipSize
        return CGRect(x: field.minX + GlassMetrics.textInset, y: field.minY + (GlassMetrics.fieldHeight - size) / 2,
                      width: size, height: size)
    }

    /// `rect` (in the window) in global AppKit coordinates.
    func onScreen(_ rect: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + rect.minX, y: windowFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
