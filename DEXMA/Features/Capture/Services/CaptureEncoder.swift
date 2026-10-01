import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a selection into the capture: cropped from the frozen screen at its native pixels
/// (never resampled), PNG with the display's colour profile, plus a thumbnail for the band's
/// chip. Takes tens of milliseconds for a big selection: call it off the main thread.
nonisolated enum CaptureEncoder {
    /// Pixels tall of the chip's thumbnail (20 pt at up to 3x, and sharp when scaled down).
    static let thumbnailHeight = 60

    static func encode(_ frozen: FrozenScreen, selection: CGRect) -> CapturedImage? {
        let imageSize = CGSize(width: frozen.image.width, height: frozen.image.height)
        let pixels = CaptureCrop.pixelRect(for: selection, displaySize: frozen.size, imageSize: imageSize)
        guard pixels.width >= 1, pixels.height >= 1, let crop = frozen.image.cropping(to: pixels),
              let png = png(crop), let thumbnail = thumbnail(crop) else { return nil }
        return CapturedImage(png: png, thumbnail: thumbnail, pixelSize: pixels.size)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func thumbnail(_ image: CGImage) -> CGImage? {
        let height = min(thumbnailHeight, image.height)
        let width = max(1, min(Int((CGFloat(image.width) * CGFloat(height) / CGFloat(max(image.height, 1))).rounded()),
                               thumbnailHeight * 2))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Wider than the chip allows: the middle, cut to fit (aspect fill).
        let scale = CGFloat(height) / CGFloat(image.height)
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(height))
        context.draw(image, in: CGRect(x: (CGFloat(width) - drawn.width) / 2, y: 0, width: drawn.width, height: drawn.height))
        return context.makeImage()
    }
}
