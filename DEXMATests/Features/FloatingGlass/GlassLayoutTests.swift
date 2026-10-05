import CoreGraphics
import Testing
@testable import DEXMA

struct GlassLayoutTests {
    /// The reference Mac's built-in display, where Spotlight's field was measured.
    private let reference = GlassLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949), buttonCount: 3)

    @Test func fieldSitsWhereSpotlightsDoes() {
        // Spotlight: 640 × 56, x 436, top 203 (from the screen's top).
        let field = reference.onScreen(reference.field)
        #expect(field == CGRect(x: 436, y: 982 - 203 - 56, width: 640, height: 56))
    }

    @Test func buttonsFollowTheFieldCentredOnIt() {
        #expect(reference.buttons.count == 3)
        #expect(reference.buttons[0] == CGRect(x: 40 + 640 + 8, y: 40 + 28 - 20, width: 40, height: 40))
        #expect(reference.buttons[2].minX - reference.buttons[1].maxX == 8)
    }

    @Test func cardBelowTheFieldAtMostSixtyPercentOfTheScreen() {
        #expect(reference.card == CGRect(x: 40, y: 40 + 56 + 8, width: 640, height: 589))
        // The window holds every shape plus the shadow's room.
        #expect(reference.windowFrame == CGRect(x: 396, y: 86, width: 864, height: 733))
    }

    @Test func cardStopsAboveTheDock() {
        let layout = GlassLayout(screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                                 visibleFrame: CGRect(x: 0, y: 70, width: 1280, height: 705), buttonCount: 3)
        let card = layout.onScreen(layout.card)
        #expect(card.minY >= 70 + GlassMetrics.bottomMargin)
        #expect(card.height == 480)
    }

    @Test func cardKeepsAMinimumOnTinyScreens() {
        let layout = GlassLayout(screenFrame: CGRect(x: 0, y: 0, width: 1024, height: 600),
                                 visibleFrame: CGRect(x: 0, y: 300, width: 1024, height: 275), buttonCount: 3)
        #expect(layout.card.height == GlassMetrics.cardMinHeight)
    }

    @Test func growingFieldPushesTheCardDownKeepingItsBottom() {
        let card = reference.card(fieldHeight: 86)
        #expect(card.minY == reference.card.minY + 30)
        #expect(card.maxY == reference.card.maxY)
        #expect(reference.card(fieldHeight: 56) == reference.card)
    }

    @Test func chipAtTheTextsStartCentredOnTheFirstLine() {
        #expect(reference.chip == CGRect(x: 40 + 61, y: 40 + 12, width: 32, height: 32))
    }

    @Test func otherDisplaysUseTheirOwnFrame() {
        let layout = GlassLayout(screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                 visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415), buttonCount: 3)
        let field = layout.onScreen(layout.field)
        #expect(abs(field.midX - 2792) < 0.001)
        #expect(1440 - field.maxY == (1440 * GlassMetrics.fieldTopFraction).rounded())
    }
}
