import CoreGraphics
import Testing
@testable import DEXMA

struct BandLayoutTests {
    private let active: [CGFloat] = [88, 82, 76]

    @Test func selectedTabExpandsOthersAreIconsAndTheIndicatorSitsBehindIt() {
        let layout = TabSwitcherLayout(activeWidths: active, progress: 1, available: 300)
        #expect(layout.labelled)
        #expect(layout.tabs.map(\.frame.width) == [30, 82, 30])
        #expect(layout.tabs.map(\.reveal) == [0, 1, 0])
        #expect(layout.tabs[0].frame == CGRect(x: 3, y: 3, width: 30, height: 26))  // 3 pt padding
        #expect(layout.tabs[1].frame.minX == CGFloat(3 + 30 + 4))  // 4 pt gap
        #expect(layout.indicator == layout.tabs[1].frame)
        #expect(layout.size == CGSize(width: 3 + 30 + 4 + 82 + 4 + 30 + 3, height: 32))
    }

    @Test func halfASwipeIsHalfExpanded() {
        let layout = TabSwitcherLayout(activeWidths: active, progress: 0.5, available: 300)
        #expect(layout.tabs[0].reveal == 0.5 && layout.tabs[1].reveal == 0.5)
        #expect(layout.tabs[0].frame.width == 59 && layout.tabs[1].frame.width == 56)
        // The indicator is between the two, its width between theirs.
        #expect(layout.indicator.minX > layout.tabs[0].frame.minX && layout.indicator.minX < layout.tabs[1].frame.minX)
        #expect(abs(layout.indicator.width - 57.5) < 0.001)
    }

    @Test func narrowBandKeepsEveryTabIconOnly() {
        let layout = TabSwitcherLayout(activeWidths: active, progress: 2, available: 120)
        #expect(!layout.labelled)
        #expect(layout.tabs.allSatisfy { $0.frame.width == 30 })
        #expect(layout.indicator == layout.tabs[2].frame)
    }

    @Test func activeWidthHugsIconAndLabel() {
        // 10 padding + 14 icon box + 6 spacing + label + 10 padding.
        #expect(TabSwitcherLayout.activeWidth(labelWidth: 50.2) == CGFloat(10 + 14 + 6 + 51 + 10))
    }

    @Test func pageDotsMorphLikeIOS() {
        let rest = PageDotsLayout(count: 3, progress: 0)
        #expect(rest.dots.map(\.frame.width) == [14, 5, 5])
        #expect(rest.dots.map(\.opacity) == [0.85, 0.25, 0.25])
        #expect(rest.dots[1].frame.minX - rest.dots[0].frame.maxX == 6)
        // Centred: total 14 + 5 + 5 + 2 × 6 = 36.
        #expect(rest.dots[0].frame.minX == -18 && rest.dots[2].frame.maxX == 18)
        let half = PageDotsLayout(count: 3, progress: 0.5)
        #expect(half.dots[0].frame.width == 9.5 && half.dots[1].frame.width == 9.5)
    }

    @Test func pathsUseTildeAndLoseTheirMiddleWhenTooLong() {
        #expect(PathAbbreviation.abbreviate("/Users/me/Documents", home: "/Users/me") == "~/Documents")
        #expect(PathAbbreviation.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(PathAbbreviation.abbreviate("/Users/meow", home: "/Users/me") == "/Users/meow")
        let measure: (String) -> CGFloat = { CGFloat($0.count) * 7 }
        let fitted = PathAbbreviation.fitMiddle("~/Documents/MAD/PROJECTS/DEXMA/Features", maxWidth: 140, measure: measure)
        #expect(fitted.count == 20 && fitted.hasPrefix("~/Documen") && fitted.hasSuffix("Features") && fitted.contains("…"))
        #expect(PathAbbreviation.fitMiddle("~/a", maxWidth: 140, measure: measure) == "~/a")
    }

    @Test func runningDotSitsBeforeTheRightAlignedDirectory() {
        let region = CGRect(x: 400, y: 0, width: 234, height: 36)
        let layout = TerminalContextLayout(directory: "/Users/me/src", home: "/Users/me", region: region) {
            CGFloat($0.count) * 6.6
        }
        #expect(layout.text == "~/src")
        #expect(layout.textFrame.maxX == region.maxX && layout.textFrame.width == 33)
        #expect(layout.dotFrame == CGRect(x: region.maxX - 33 - 6 - 6, y: 15, width: 6, height: 6))
    }
}
