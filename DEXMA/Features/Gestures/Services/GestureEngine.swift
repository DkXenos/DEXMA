import Foundation
import OpenMultitouchSupport
import OpenMultitouchSupportXCF

/// Raw trackpad touches (OpenMultitouchSupport) → `GestureRecognizer` → the `SwipeTarget`
/// (the notch panel). If multitouch isn't available the engine simply stays off; the hotkey
/// still works.
final class GestureEngine {
    private let target: any SwipeTarget
    private var recognizer = GestureRecognizer()
    private var task: Task<Void, Never>?

    var parameters = GestureParameters()
    /// Escape hatch in case a trackpad reports y = 0 at the top edge.
    var invertsY = false
    /// Told when scroll events should be swallowed (the scroll blocker reads it).
    var scrollGate: ScrollGate?
    /// Live touches, for the Settings trackpad preview.
    var onTouches: (([TouchPoint]) -> Void)?

    private(set) var isRunning = false
    private var wasCapturing = false

    init(target: any SwipeTarget) {
        self.target = target
    }

    /// Returns false (and stays off) when there is no multitouch device or it can't start.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard OpenMTManager.systemSupportsMultitouch(), OMSManager.shared.startListening() else {
            return false
        }
        isRunning = true
        let stream = OMSManager.shared.touchDataStream
        task = Task { [weak self] in
            for await frame in stream {
                self?.handle(frame)
            }
        }
        return true
    }

    func stop() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        OMSManager.shared.stopListening()
        isRunning = false
        recognizer.reset()
        setCapturing(false)
    }

    private func handle(_ frame: [OMSTouchData]) {
        // `making`/`touching` are fingers in contact; the other states are hovering or lifting.
        let touches = frame.compactMap { touch -> TouchPoint? in
            guard touch.state == .making || touch.state == .touching else { return nil }
            let y = CGFloat(touch.position.y)
            return TouchPoint(id: touch.id, x: CGFloat(touch.position.x), y: invertsY ? 1 - y : y)
        }
        onTouches?(touches)

        let event = recognizer.update(
            touches: touches, time: ProcessInfo.processInfo.systemUptime,
            panelOpen: target.isOpen, canClose: target.canCloseBySwipe, parameters: parameters)
        switch event {
        case .began: target.beginInteraction()
        case .changed(let delta): target.updateInteraction(delta: delta)
        case .ended(_, let velocity): target.endInteraction(velocity: velocity)
        case .cancelled: target.endInteraction(velocity: 0)
        case nil: break
        }
        var swipeCompleted = false
        if case .ended = event { swipeCompleted = true }
        setCapturing(recognizer.isCapturing, swipeCompleted: swipeCompleted)
    }

    private func setCapturing(_ capturing: Bool, swipeCompleted: Bool = false) {
        guard capturing != wasCapturing else { return }
        wasCapturing = capturing
        // Fingers just landed on the top edge: a swipe may follow, get the screen warp ready.
        if capturing { target.prepareForMotion() }
        scrollGate?.setCapturing(capturing, swipeCompleted: swipeCompleted)
    }
}
