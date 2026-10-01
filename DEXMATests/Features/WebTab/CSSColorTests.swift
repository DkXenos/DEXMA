import CoreGraphics
import Testing
@testable import DEXMA

struct CSSColorTests {
    @Test func parsesComputedStyleColours() throws {
        let dark = try #require(CSSColor("rgb(28, 28, 30)"))
        #expect(abs(dark.red - 28.0 / 255) < 0.0001 && abs(dark.blue - 30.0 / 255) < 0.0001 && dark.alpha == 1)
        let clear = try #require(CSSColor("rgba(0, 0, 0, 0)"))
        #expect(clear.isTransparent)
        let modern = try #require(CSSColor("rgb(255 255 255 / 0.5)"))
        #expect(modern.alpha == 0.5 && modern.green == 1)
        #expect(CSSColor("transparent") == nil && CSSColor("#1c1c1e") == nil && CSSColor("rgb(1,2)") == nil)
    }
}
