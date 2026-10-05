#if DEBUG
import AppKit
import CoreImage
import ScreenCaptureKit

/// Debug-only: records a region of the real screen (DEXMA included) as a series of frames, through
/// a ScreenCaptureKit stream at the display's pace, to see an animation frame by frame. Needs
/// DEXMA's Screen Recording grant (launch with `open`).
final class FrameRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "FrameRecorder")
    private let box = FrameBox()

    /// Starts recording `rect` (global AppKit coordinates) on `screen`, `scale` pixels per point.
    func start(screen: NSScreen, rect: CGRect, scale: CGFloat = 1) async -> Bool {
        guard let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return false }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                          width: rect.width, height: rect.height)
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            return false
        }
        self.stream = stream
        return true
    }

    /// Stops and returns the frames since `start` (or since `clear`): host time, picture.
    func stop() async -> [(CFTimeInterval, CGImage)] {
        try? await stream?.stopCapture()
        stream = nil
        return box.take()
    }

    /// Drops what was recorded so far (the stream's first frames, before the animation).
    func clear() {
        _ = box.take()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let picture = box.context.createCGImage(image, from: image.extent) else { return }
        box.append((CACurrentMediaTime(), picture))
    }
}

/// The frames, filled on the stream's queue, taken on the main thread.
private nonisolated final class FrameBox: @unchecked Sendable {
    let context = CIContext()
    private let lock = NSLock()
    private var frames: [(CFTimeInterval, CGImage)] = []

    func append(_ frame: (CFTimeInterval, CGImage)) {
        lock.lock()
        frames.append(frame)
        lock.unlock()
    }

    func take() -> [(CFTimeInterval, CGImage)] {
        lock.lock()
        defer { lock.unlock() }
        let taken = frames
        frames = []
        return taken
    }
}
#endif
