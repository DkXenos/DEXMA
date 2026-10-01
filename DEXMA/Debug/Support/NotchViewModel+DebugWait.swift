#if DEBUG
extension NotchViewModel {
    /// Waits up to 4 s for the spring and the liquid effect to come to rest. False on timeout.
    func waitForRest() async -> Bool {
        for _ in 0..<400 {
            try? await Task.sleep(for: .milliseconds(10))
            if !debugDriver.isAnimating, !effects.isActive { return true }
        }
        return false
    }
}
#endif
