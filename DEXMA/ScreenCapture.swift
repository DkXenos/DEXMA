import AppKit
import CoreMedia
import CoreVideo
import os
import ScreenCaptureKit

/// Streams the screen region under the panel (DEXMA's own windows and the cursor left out)
/// so `ScreenWarpView` can redraw it bent. Runs only around motion and hover — macOS shows its
/// screen-recording indicator while it does — and needs Screen Recording permission.
///
/// Frames arrive on a private queue; the newest one is kept (retaining its pixel buffer, so
/// ScreenCaptureKit doesn't reuse it while it's drawn) behind a lock.
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DEXMA",
                                       category: "ScreenCapture")

    nonisolated private struct Shared {
        var latest: CVPixelBuffer?
        var generation = 0
        var firstFrameTime: CFTimeInterval?
        var lastFrameTime: CFTimeInterval?
        var frameCount = 0
        var longestGap: CFTimeInterval = 0
    }

    nonisolated private let shared = OSAllocatedUnfairLock(uncheckedState: Shared())
    nonisolated private let queue = DispatchQueue(label: "DEXMA screen capture", qos: .userInteractive)

    private var stream: SCStream?
    private var isStarting = false
    private var target: (displayID: CGDirectDisplayID, rect: CGRect, pixels: CGSize)?
    /// When the last `start` was asked for, for measuring start-up latency.
    private(set) var requestTime: CFTimeInterval = 0

    var isRunning: Bool { stream != nil }
    /// The user stopped the stream from macOS's recording indicator.
    var onUserStopped: (() -> Void)?

    /// The newest frame and a number that changes whenever it does.
    func latestFrame() -> (buffer: CVPixelBuffer, generation: Int)? {
        shared.withLockUnchecked { state in state.latest.map { ($0, state.generation) } }
    }

    /// Frame statistics since the stream (re)started: first-frame time, count, longest gap.
    func statistics() -> (firstFrame: CFTimeInterval?, frames: Int, longestGap: CFTimeInterval) {
        shared.withLockUnchecked { ($0.firstFrameTime, $0.frameCount, $0.longestGap) }
    }

    /// Captures `rect` (global AppKit coordinates) of `screen`, starting the stream if needed or
    /// pointing a running one at the new rect.
    func start(rect: CGRect, on screen: NSScreen) {
        guard let displayID = screen.displayID else { return }
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        let pixels = CGSize(width: (rect.width * screen.backingScaleFactor).rounded(),
                            height: (rect.height * screen.backingScaleFactor).rounded())
        let wanted = (displayID: displayID, rect: local, pixels: pixels)
        if let target, target.displayID == displayID, target.rect == local, target.pixels == pixels,
           stream != nil || isStarting {
            return
        }
        if let stream, target?.displayID == displayID {
            target = wanted
            stream.updateConfiguration(Self.configuration(for: wanted, screen: screen)) { error in
                if let error { Self.logger.error("Retarget failed: \(error.localizedDescription, privacy: .public)") }
            }
            return
        }
        guard !isStarting else {
            target = wanted  // The starting stream picks this up when it's running.
            return
        }
        stopStream()
        target = wanted
        isStarting = true
        requestTime = CACurrentMediaTime()
        shared.withLockUnchecked { $0 = Shared() }
        let colorSpace = screen.colorSpace?.cgColorSpace?.name
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let self else { return }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    self.isStarting = false
                    return
                }
                let mine = content.applications.filter { $0.processID == getpid() }
                let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
                let configuration = Self.configuration(for: wanted, screen: nil)
                if let colorSpace { configuration.colorSpaceName = colorSpace }
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                try await stream.startCapture()
                self.isStarting = false
                // Stopped or retargeted to another display while starting: don't keep it.
                guard self.target?.displayID == displayID else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                if let target = self.target, target.rect != wanted.rect || target.pixels != wanted.pixels {
                    try? await stream.updateConfiguration(Self.configuration(for: target, screen: nil))
                }
            } catch {
                self?.isStarting = false
                Self.logger.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        target = nil
        stopStream()
    }

    private func stopStream() {
        guard let stream else { return }
        self.stream = nil
        shared.withLockUnchecked { $0.latest = nil }
        Task { try? await stream.stopCapture() }
    }

    private static func configuration(for target: (displayID: CGDirectDisplayID, rect: CGRect, pixels: CGSize),
                                      screen: NSScreen?) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = target.rect
        configuration.width = Int(target.pixels.width)
        configuration.height = Int(target.pixels.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false  // The real cursor is drawn above everything anyway.
        configuration.queueDepth = 4
        configuration.captureResolution = .best
        if let name = screen?.colorSpace?.cgColorSpace?.name { configuration.colorSpaceName = name }
        return configuration
    }

    // MARK: SCStreamOutput / SCStreamDelegate (on the capture queue)

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete || status == .started,
              let buffer = sampleBuffer.imageBuffer else { return }
        let now = CACurrentMediaTime()
        shared.withLockUnchecked { state in
            state.latest = buffer
            state.generation &+= 1
            if state.firstFrameTime == nil { state.firstFrameTime = now }
            if let last = state.lastFrameTime { state.longestGap = max(state.longestGap, now - last) }
            state.lastFrameTime = now
            state.frameCount += 1
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.logger.error("Screen capture stopped: \(error.localizedDescription, privacy: .public)")
        let stopped = ObjectIdentifier(stream)
        let byUser = (error as NSError).code == SCStreamError.Code.userStopped.rawValue
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == stopped else { return }
            self.stream = nil
            self.target = nil
            self.shared.withLockUnchecked { $0.latest = nil }
            if byUser { self.onUserStopped?() }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
