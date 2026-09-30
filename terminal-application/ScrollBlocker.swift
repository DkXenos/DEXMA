import AppKit
import ApplicationServices
import os

/// Shared between the gesture engine (main thread) and the event tap's own thread.
nonisolated final class ScrollGate: Sendable {
    private struct State {
        var capturing = false
        var swallowMomentumUntil: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `swipeCompleted`: the fingers just lifted from a real NotchTerm swipe, so the momentum
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

/// Swallows trackpad scroll events while a NotchTerm swipe is in progress, so the window under
/// the cursor doesn't scroll along. Needs Accessibility (an event tap that drops events); until
/// that's granted it polls, and starts by itself the moment it is — no relaunch.
final class ScrollBlocker {
    let gate = ScrollGate()
    private(set) var isActive = false
    var onActiveChange: ((Bool) -> Void)?
    private var pollTimer: Timer?
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchTerm",
                                       category: "ScrollBlocker")

    func startWhenPermitted() {
        guard !isActive, pollTimer == nil else { return }
        if tryStart() { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {  // Scheduled on the main run loop.
                guard let self, self.tryStart() else { return }
                self.pollTimer?.invalidate()
                self.pollTimer = nil
            }
        }
    }

    private func tryStart() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else { return false }
        let context = TapContext(gate: gate)
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: scrollTapCallback,
                                           userInfo: Unmanaged.passRetained(context).toOpaque())
        else {
            Self.logger.error("CGEvent.tapCreate failed although Accessibility is granted")
            return false
        }
        context.port = port
        // Its own thread: a busy main thread must never delay scrolling system-wide.
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "NotchTerm scroll tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        isActive = true
        onActiveChange?(true)
        return true
    }
}

/// Lives for the life of the process (retained once, passed to the tap as userInfo).
private nonisolated final class TapContext: @unchecked Sendable {
    let gate: ScrollGate
    /// Written once, before the tap's thread starts.
    var port: CFMachPort?

    init(gate: ScrollGate) {
        self.gate = gate
    }
}

private nonisolated func scrollTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                                           event: CGEvent, userInfo: UnsafeMutableRawPointer?)
    -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // macOS switches a slow tap off; switch it straight back on.
        if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
    case .scrollWheel:
        // Only trackpad (continuous) scrolling can belong to a swipe; mouse wheels pass.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { break }
        let isMomentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        if context.gate.shouldSwallow(isMomentum: isMomentum) { return nil }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
