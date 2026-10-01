#if DEBUG
import AppKit
import ScreenCaptureKit

/// Pictures for the debug harnesses: the window server's own composite of a window, pixel
/// comparisons and PNG output.
enum DebugImages {
    /// `window` as the window server composited it. Looked up at runtime: the API is
    /// deprecated since macOS 14 (fine for a debug check, not for shipping). An app may
    /// capture its own windows without Screen Recording permission.
    static func window(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // includingWindow = 1 << 3; boundsIgnoreFraming = 1 << 0, bestResolution = 1 << 3.
        return capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }

    /// The real screen (DEXMA included) around `panel`, through ScreenCaptureKit: needs
    /// DEXMA's Screen Recording grant (launch with `open`, not from a shell).
    static func screen(around panel: NSPanel) async -> CGImage? {
        guard let screen = panel.screen, let displayID = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let rect = panel.frame
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                          width: rect.width, height: rect.height)
        configuration.width = Int(rect.width * screen.backingScaleFactor)
        configuration.height = Int(rect.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// `image` over opaque black, the way the live terminal shows over the silhouette.
    static func overBlack(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Pixels that differ by more than 2/255 in any of the first `channels` (of RGBA), the
    /// largest difference in those channels, and the box around the differing pixels. Nil if
    /// the sizes don't match.
    static func difference(_ a: CGImage, _ b: CGImage, channels: Int) -> (differing: Int, maxDiff: Int, box: String)? {
        guard a.width == b.width, a.height == b.height else { return nil }
        let pa = rgba(a), pb = rgba(b)
        var differing = 0, maxDiff = 0
        var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<channels { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            maxDiff = max(maxDiff, d)
            if d > 2 {
                differing += 1
                let x = (i / 4) % a.width, y = (i / 4) / a.width
                box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
            }
        }
        return (differing, maxDiff, differing == 0 ? "" : "x \(box.minX)…\(box.maxX) y \(box.minY)…\(box.maxY)")
    }

    /// The box (in pixels) around every pixel that differs by more than 2/255 in any channel,
    /// nil if none do or the sizes don't match.
    static func differenceBox(_ a: CGImage, _ b: CGImage) -> CGRect? {
        guard a.width == b.width, a.height == b.height else { return nil }
        let pa = rgba(a), pb = rgba(b)
        var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            guard d > 2 else { continue }
            let x = (i / 4) % a.width, y = (i / 4) / a.width
            box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
        }
        guard box.maxX >= 0 else { return nil }
        return CGRect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY)
    }

    /// Writes `<dir>/<name>.png`.
    static func write(_ image: CGImage, _ dir: URL, _ name: String) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent("\(name).png"))
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}
#endif
