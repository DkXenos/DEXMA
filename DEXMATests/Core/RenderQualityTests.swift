import Testing
@testable import DEXMA

struct RenderQualityTests {
    @Test func eachStopRunsLessOfTheScreenWarp() {
        #expect(!RenderQuality.performance.warps && !RenderQuality.performance.warpsAtRest)
        #expect(RenderQuality.balanced.warps && !RenderQuality.balanced.warpsAtRest)
        #expect(RenderQuality.quality.warps && RenderQuality.quality.warpsAtRest)
        // The slider's stops, left to right.
        #expect(RenderQuality.allCases.map(\.rawValue) == [0, 1, 2])
    }
}
