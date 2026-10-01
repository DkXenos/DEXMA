import CoreGraphics
import Foundation

/// A finished capture: the selection cropped from the frozen screen at native pixels, as PNG,
/// plus a small picture of it for the band's chip. In memory only.
nonisolated struct CapturedImage: Sendable {
    let png: Data
    let thumbnail: CGImage
    /// The crop's size in pixels.
    let pixelSize: CGSize

    var aspect: CGFloat {
        pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 1
    }
}
