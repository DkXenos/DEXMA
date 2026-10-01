#if DEBUG
import AppKit

/// Frame timing while the panel animates, from creation until `stop`: every display-link
/// frame of its spring (vsync time, and main-thread time spent in the step), and the length
/// of each main run-loop pass while animating, which includes SwiftUI's render and commit.
final class FramePacingProbe {
    /// Vsync times of the current series (see `startSeries`).
    private(set) var stamps: [CFTimeInterval] = []
    /// Milliseconds per step, over all series.
    private(set) var stepTimes: [Double] = []
    /// Milliseconds per run-loop pass while animating, over all series.
    private(set) var passes: [Double] = []
    private let driver: SpringDriver
    private var observer: CFRunLoopObserver?

    init(driver: SpringDriver) {
        self.driver = driver
        var passStart: CFTimeInterval = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { passStart = now } else if passStart > 0, let self, self.driver.isAnimating {
                self.passes.append((now - passStart) * 1000)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
        driver.debugFrameLog = { [weak self] stamp, duration in
            self?.stamps.append(stamp)
            self?.stepTimes.append(duration * 1000)
        }
    }

    /// A new open or close: `stamps` starts over.
    func startSeries() {
        stamps.removeAll()
    }

    func stop() {
        driver.debugFrameLog = nil
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
}
#endif
