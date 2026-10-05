import CoreGraphics
import Testing
@testable import DEXMA

struct SliderTrackTests {
    private let track = SliderTrack(width: 228, height: 28)

    @Test func fillGrowsFromTheIconCircleToTheFullWidth() {
        #expect(track.fillWidth(for: 0) == 28)
        #expect(track.fillWidth(for: 1) == 228)
        #expect(track.fillWidth(for: 0.5) == 128)
        #expect(track.fillWidth(for: -1) == 28 && track.fillWidth(for: 2) == 228)  // Clamped.
    }

    @Test func pointerSetsTheValueUnderIt() {
        #expect(track.value(at: 14) == 0)    // The circle's middle.
        #expect(track.value(at: 214) == 1)   // The far end, less half a circle.
        #expect(track.value(at: 114) == 0.5)
        #expect(track.value(at: -50) == 0 && track.value(at: 500) == 1)
        // Dropping the pointer where a value's fill ends gives that value back.
        #expect(abs(track.value(at: track.fillWidth(for: 0.3) - 14) - 0.3) < 1e-9)
        #expect(SliderTrack(width: 20, height: 28).value(at: 10) == 0)  // Too narrow to slide.
    }
}
