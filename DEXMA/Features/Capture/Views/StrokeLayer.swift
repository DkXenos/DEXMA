import QuartzCore

/// The user's stroke while drawing — white, round caps, a soft glow (wider, fainter white strokes
/// beneath) with colour shimmering along it — and then the outline it morphs into around the
/// selection.
///
/// Long scribbles stay cheap: the curve is cut into chunks of `chunkSize` segments. A finished
/// chunk never changes again (Core Animation keeps its rendering), so each pointer move redraws
/// only the last, short chunk. Each tier (glows, shimmer mask, core) is a group whose opacity
/// applies to the group as a whole, so chunks overlapping where they join (or the stroke
/// crossing itself) never double up.
final class StrokeLayer: CALayer {
    private static let chunkSize = 48

    private var look = CaptureLook.full
    private(set) var points: [CGPoint] = []
    /// Segments before this index are in finished chunks.
    private var committed = 0
    /// Bottom to top: the glows (widest first), the shimmer (masked by the stroke), the core.
    private var glowGroups: [CALayer] = []
    private let shimmer = CALayer()
    private let shimmerColors = CAGradientLayer()
    private let shimmerMask = CALayer()
    private let core = CALayer()
    /// The chunk being drawn (or, once released, the whole stroke): a shape per tier.
    private var live: [CAShapeLayer] = []

    override init() {
        super.init()
        setUp()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUp() {
        for _ in look.glowWidths {
            let group = CALayer()
            group.allowsGroupOpacity = true
            addSublayer(group)
            glowGroups.append(group)
        }
        shimmer.mask = shimmerMask
        shimmer.addSublayer(shimmerColors)
        addSublayer(shimmer)
        core.allowsGroupOpacity = true
        addSublayer(core)
    }

    /// Before each capture: the look, the display's size and scale, and whether the shimmer may
    /// move.
    func configure(look: CaptureLook, size: CGSize, scale: CGFloat, animated: Bool) {
        self.look = look
        contentsScale = scale
        withoutAnimation {
            frame = CGRect(origin: .zero, size: size)
            for (group, opacity) in zip(glowGroups, look.glowOpacities) {
                group.frame = bounds
                group.opacity = Float(opacity)
            }
            core.frame = bounds
            shimmer.frame = bounds
            shimmerMask.frame = bounds
            shimmer.opacity = Float(look.shimmer)
            shimmer.isHidden = look.shimmer <= 0
            configureShimmer(size: size, animated: animated && look.shimmer > 0)
        }
        reset()
    }

    /// Soft tints (Apple Intelligence's blue, lavender, pink) in a pattern that repeats every
    /// display width, slid left by one width per period: a seamless loop, run by Core Animation.
    private func configureShimmer(size: CGSize, animated: Bool) {
        let tints = [CGColor(red: 0.55, green: 0.80, blue: 1, alpha: 1), CGColor(red: 0.76, green: 0.62, blue: 1, alpha: 1),
                     CGColor(red: 1, green: 0.62, blue: 0.86, alpha: 1)]
        let clear = CGColor(red: 1, green: 1, blue: 1, alpha: 0)
        var colors: [CGColor] = []
        for _ in 0..<2 {
            for tint in tints { colors += [clear, tint] }
        }
        colors.append(clear)
        shimmerColors.colors = colors
        shimmerColors.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerColors.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerColors.contentsScale = 0.5  // Soft colour: half resolution is plenty.
        shimmerColors.frame = CGRect(x: 0, y: 0, width: size.width * 2, height: size.height)
        shimmerColors.removeAllAnimations()
        guard animated else { return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = size.width
        slide.toValue = 0
        slide.duration = look.shimmerPeriod
        slide.repeatCount = .infinity
        shimmerColors.add(slide, forKey: "shimmer")
    }

    // MARK: Drawing

    func begin(at point: CGPoint) {
        reset()
        points = [point]
        redrawLive()
    }

    /// The pointer moved on to `point`. Ignored closer than `StrokeGeometry.minimumSpacing` to
    /// the last point (jitter).
    func add(_ point: CGPoint) {
        guard let last = points.last else { return begin(at: point) }
        guard hypot(point.x - last.x, point.y - last.y) >= StrokeGeometry.minimumSpacing else { return }
        points.append(point)
        // Segment i is final once the point after its end exists (its tangent needs it).
        if points.count - 2 - committed >= Self.chunkSize {
            let end = points.count - 2
            withoutAnimation { addChunk(segments: committed..<end) }
            committed = end
        }
        redrawLive()
    }

    func reset() {
        withoutAnimation {
            for group in glowGroups + [core, shimmerMask] {
                group.sublayers?.forEach { $0.removeFromSuperlayer() }
            }
            live = []
            transform = CATransform3DIdentity
            opacity = 1
        }
        removeAllAnimations()
        points = []
        committed = 0
    }

    /// One shape per tier for these segments, sized to the chunk's own bounds (not the display's).
    private func addChunk(segments: Range<Int>) {
        let path = StrokeGeometry.path(through: points, segments: segments)
        for (shape, parent) in zip(makeShapes(), tierParents) {
            place(shape, path: path)
            parent.addSublayer(shape)
        }
    }

    private func redrawLive() {
        withoutAnimation {
            if live.isEmpty {
                live = makeShapes()
                for (shape, parent) in zip(live, tierParents) { parent.addSublayer(shape) }
            }
            let segments = points.count > 1 ? committed..<(points.count - 1) : nil
            let path = StrokeGeometry.path(through: points, segments: segments)
            for shape in live { place(shape, path: path) }
        }
    }

    /// Glows, then the shimmer's mask, then the core: matches `makeShapes`.
    private var tierParents: [CALayer] {
        glowGroups + [shimmerMask, core]
    }

    private func makeShapes() -> [CAShapeLayer] {
        let widths = look.glowWidths + [look.glowWidths.first ?? look.strokeWidth, look.strokeWidth]
        return widths.map { width in
            let shape = CAShapeLayer()
            shape.fillColor = nil
            shape.strokeColor = CGColor(gray: 1, alpha: 1)
            shape.lineWidth = width
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.contentsScale = contentsScale
            return shape
        }
    }

    private func place(_ shape: CAShapeLayer, path: CGPath) {
        let box = path.boundingBoxOfPath.insetBy(dx: -shape.lineWidth, dy: -shape.lineWidth)
        shape.frame = box
        var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        shape.path = path.copy(using: &shift)
    }

    // MARK: Release

    /// The stroke morphs into a rounded rectangle around `rect` (thinner, as an outline).
    /// Without motion the outline just appears.
    func morph(into rect: CGRect, duration: Double, animated: Bool) {
        let length = StrokeGeometry.length(points)
        let radius = min(look.selectionRadius, rect.width / 2, rect.height / 2)
        let perimeter = StrokeGeometry.perimeter(rect, radius: radius)
        let count = min(max(Int(max(length, perimeter) / 3), 120), 1500)
        let from = StrokeGeometry.resample(points.count > 1 ? points : [points.first ?? rect.origin, points.first ?? rect.origin],
                                           count: count)
        let to = StrokeGeometry.roundedRectPoints(rect, radius: radius, count: count, startingNear: from[0],
                                                  clockwise: StrokeGeometry.isClockwise(points))
        showOutline(from: animated ? StrokeGeometry.path(through: from) : nil, to: StrokeGeometry.path(through: to),
                    duration: duration)
    }

    /// A click picked a window: its outline fades in, settling from slightly larger.
    func outline(_ rect: CGRect, duration: Double, animated: Bool) {
        let radius = min(look.selectionRadius, rect.width / 2, rect.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        showOutline(from: nil, to: path, duration: duration)
        guard animated else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.duration = duration * 0.6
        add(fade, forKey: "outlineFade")
    }

    /// Every chunk replaced by one full-display shape per tier, morphing from `from` (nil: no
    /// morph) to `to`, the core thinning to the outline's width.
    private func showOutline(from: CGPath?, to: CGPath, duration: Double) {
        withoutAnimation {
            for group in tierParents { group.sublayers?.forEach { $0.removeFromSuperlayer() } }
            live = makeShapes()
            for (shape, parent) in zip(live, tierParents) {
                shape.frame = bounds
                shape.path = to
                parent.addSublayer(shape)
            }
            live.last?.lineWidth = look.outlineWidth
        }
        guard let from else { return }
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        for (index, shape) in live.enumerated() {
            let morph = CABasicAnimation(keyPath: "path")
            morph.fromValue = from
            morph.duration = duration
            morph.timingFunction = timing
            shape.add(morph, forKey: "morph")
            if index == live.count - 1 {
                let thin = CABasicAnimation(keyPath: "lineWidth")
                thin.fromValue = look.strokeWidth
                thin.duration = duration
                thin.timingFunction = timing
                shape.add(thin, forKey: "thin")
            }
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
