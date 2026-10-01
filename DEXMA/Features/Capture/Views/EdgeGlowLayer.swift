import QuartzCore

/// Capture mode's sign: a soft band of colour along the display's edges, slowly turning, like
/// Apple Intelligence's edge glow. A conic gradient masked by a falloff from the edges; turning
/// and breathing are Core Animation's, so it costs the main thread nothing while it runs. Both
/// are bitmaps rendered once (small: they're soft), so turning them is only compositing.
///
/// Masked content that moves is re-rendered offscreen every frame, so the glow is four strips
/// along the edges (each its own copy of the gradient, all turning about the display's centre),
/// not one display-sized layer: the window server only redraws the edges.
final class EdgeGlowLayer: CALayer {
    private static let colors = [(0.30, 0.62, 1.0), (0.62, 0.42, 1.0), (1.0, 0.40, 0.70), (1.0, 0.62, 0.32),
                                 (0.40, 0.85, 0.95), (0.30, 0.62, 1.0)]
        .map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    /// Rendered once, shared by the four strips.
    private static let wheel = conicImage(side: 256)

    private var strips: [(strip: CALayer, colors: CALayer, mask: CALayer)] = []
    private var falloff: CGImage?
    private var maskSize = CGSize.zero
    private var maskWidth: CGFloat = 0

    override init() {
        super.init()
        for _ in 0..<4 {
            let strip = CALayer()
            let colors = CALayer()
            colors.contents = Self.wheel
            colors.contentsGravity = .resize
            let mask = CALayer()
            mask.contentsGravity = .resize
            strip.addSublayer(colors)
            strip.mask = mask
            addSublayer(strip)
            strips.append((strip, colors, mask))
        }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Before each capture: the display's size, the look (its `edgeGlow` opacity: 0 hides it) and
    /// whether it may move.
    func configure(size: CGSize, look: CaptureLook, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(origin: .zero, size: size)
        isHidden = look.edgeGlow <= 0
        if maskSize != size || maskWidth != look.edgeGlowWidth {
            maskSize = size
            maskWidth = look.edgeGlowWidth
            falloff = Self.falloffImage(size: size, width: look.edgeGlowWidth)
        }
        // How far in the falloff still shows (the blur reaches about twice its radius).
        let band = min((look.edgeGlowWidth * 2.2).rounded(.up), size.height / 2, size.width / 2)
        let rects = [CGRect(x: 0, y: 0, width: size.width, height: band),
                     CGRect(x: 0, y: size.height - band, width: size.width, height: band),
                     CGRect(x: 0, y: band, width: band, height: size.height - 2 * band),
                     CGRect(x: size.width - band, y: band, width: band, height: size.height - 2 * band)]
        // A square the display's diagonal across, centred on the display, so turning never shows
        // its corners.
        let side = hypot(size.width, size.height)
        for ((strip, colors, mask), rect) in zip(strips, rects) {
            strip.frame = rect
            colors.frame = CGRect(x: (size.width - side) / 2 - rect.minX, y: (size.height - side) / 2 - rect.minY,
                                  width: side, height: side)
            mask.frame = strip.bounds
            mask.contents = falloff
            mask.contentsRect = CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                                       width: rect.width / size.width, height: rect.height / size.height)
        }
        CATransaction.commit()
        for (_, colors, _) in strips { colors.removeAllAnimations() }
        guard animated, !isHidden else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.byValue = 2 * Double.pi
        turn.duration = look.edgeGlowPeriod
        turn.repeatCount = .infinity
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.7
        breathe.toValue = 1
        breathe.duration = 1.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // The same begin time: the four copies turn as one.
        let begin = convertTime(CACurrentMediaTime(), from: nil)
        turn.beginTime = begin
        breathe.beginTime = begin
        for (_, colors, _) in strips {
            colors.add(turn, forKey: "turn")
            colors.add(breathe, forKey: "breathe")
        }
    }

    /// The colour wheel: the gradient's colours around its centre (it's scaled up a lot; the
    /// colours are soft, so it doesn't show).
    private static func conicImage(side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                        locations: nil) else { return nil }
        CGContextDrawConicGradient(context, gradient, CGPoint(x: side / 2, y: side / 2), .pi / 2)
        return context.makeImage()
    }

    /// White at the display's edge fading to nothing `width` points in (an inner shadow), drawn
    /// at a quarter of the points: Core Animation scales it up smoothly.
    private static func falloffImage(size: CGSize, width: CGFloat) -> CGImage? {
        let scale: CGFloat = 0.25
        let pixels = CGSize(width: max((size.width * scale).rounded(), 1), height: max((size.height * scale).rounded(), 1))
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let inner = CGRect(origin: .zero, size: pixels)
        let ring = CGMutablePath()
        ring.addRect(inner.insetBy(dx: -pixels.width, dy: -pixels.height))
        ring.addRect(inner)
        context.setShadow(offset: .zero, blur: width * scale, color: CGColor(gray: 1, alpha: 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        // Twice: a brighter edge, the same reach.
        for _ in 0..<2 {
            context.addPath(ring)
            context.fillPath(using: .evenOdd)
        }
        return context.makeImage()
    }
}
