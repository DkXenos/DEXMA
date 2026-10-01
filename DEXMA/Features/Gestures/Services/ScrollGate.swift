import Foundation
import os

/// Shared between the gesture engine (main thread) and the event tap's own thread.
nonisolated final class ScrollGate: Sendable {
    private struct State {
        var capturing = false
        var swallowMomentumUntil: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `swipeCompleted`: the fingers just lifted from a real DEXMA swipe, so the momentum
    /// scroll macOS generates afterwards belongs to it too.
    func setCapturing(_ capturing: Bool, swipeCompleted: Bool = false) {
        state.withLock { state in
            state.capturing = capturing
            if !capturing, swipeCompleted {
                state.swallowMomentumUntil = ProcessInfo.processInfo.systemUptime + 0.6
            }
        }
    }

    func shouldSwallow(isMomentum: Bool) -> Bool {
        state.withLock { state in
            state.capturing
                || (isMomentum && ProcessInfo.processInfo.systemUptime < state.swallowMomentumUntil)
        }
    }
}
