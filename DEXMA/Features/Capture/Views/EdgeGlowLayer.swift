import QuartzCore

/// Capture mode's sign: a soft band of colour along the display's edges, slowly turning, like
/// Apple Intelligence's edge glow. A conic gradient (half resolution: it's soft anyway) masked by
/// a pre-rendered falloff from the edges; turning and breathing are Core Animation's, so it costs
/// the main thread nothing while it runs.
final class EdgeGlowLayer: CALayer {
    private let colors = CAGradientLayer()
    private let falloff = CALayer()
    private var maskSize = CGSize.zero
    private var maskWidth: CGFloat = 0

    override init() {
        super.init()
        colors.type = .conic
        colors.startPoint = CGPoint(x: 0.5, y: 0.5)
        colors.endPoint = CGPoint(x: 0.5, y: 0)
        colors.colors = [(0.30, 0.62, 1.0), (0.62, 0.42, 1.0), (1.0, 0.40, 0.70), (1.0, 0.62, 0.32),
                         (0.40, 0.85, 0.95), (0.30, 0.62, 1.0)]
            .map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
        colors.contentsScale = 0.5
        addSublayer(colors)
        mask = falloff
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
        // A square the display's diagonal across, so turning never shows its corners.
        let side = hypot(size.width, size.height)
        colors.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        falloff.frame = bounds
        if maskSize != size || maskWidth != look.edgeGlowWidth {
            maskSize = size
            maskWidth = look.edgeGlowWidth
            falloff.contents = Self.falloffImage(size: size, width: look.edgeGlowWidth)
        }
        CATransaction.commit()
        colors.removeAllAnimations()
        guard animated, !isHidden else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.byValue = 2 * Double.pi
        turn.duration = look.edgeGlowPeriod
        turn.repeatCount = .infinity
        colors.add(turn, forKey: "turn")
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.7
        breathe.toValue = 1
        breathe.duration = 1.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        colors.add(breathe, forKey: "breathe")
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
