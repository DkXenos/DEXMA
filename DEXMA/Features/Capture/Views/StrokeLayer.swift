import QuartzCore

/// The user's stroke while drawing — white, round caps, a soft glow (wider, fainter white strokes
/// beneath) with colour shimmering along it — and then the outline it morphs into around the
/// selection.
///
/// Long scribbles stay cheap: the curve is cut into chunks of `chunkSize` segments. A finished
/// chunk never changes again (Core Animation keeps its rendering), so each pointer move redraws
/// only the last, short chunk. Each tier (glows, shimmer mask, core) is a group whose opacity
/// applies to the group as a whole, so chunks overlapping where they join (or the stroke
/// crossing itself) never double up. Those groups and the shimmer are redrawn offscreen whenever
/// their content moves, so they only ever cover the stroke's own extent, not the display.
final class StrokeLayer: CALayer {
    private static let chunkSize = 48
    /// The most points a morphing path has (each one a curve the render server strokes per frame).
    private static let morphPoints = 480

    private var look = CaptureLook.full
    private(set) var points: [CGPoint] = []
    /// Segments before this index are in finished chunks.
    private var committed = 0
    /// Bottom to top: the glows (widest first), the shimmer (masked by the stroke), the core.
    private var glowGroups: [CALayer] = []
    private let shimmer = CALayer()
    /// A bitmap, rendered once per capture: sliding it is only compositing.
    private let shimmerColors = CALayer()
    private let shimmerMask = CALayer()
    private let core = CALayer()
    /// The chunk being drawn (or, once released, the whole stroke): a shape per tier.
    private var live: [CAShapeLayer] = []
    /// What the stroke (with its widest glow) covers so far, in the display's points.
    private var extent = CGRect.null

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
        shimmer.masksToBounds = true  // The sliding colours only where the stroke is.
        shimmerColors.contentsGravity = .resize
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
            for (group, opacity) in zip(glowGroups, look.glowOpacities) { group.opacity = Float(opacity) }
            shimmer.opacity = Float(look.shimmer)
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
        shimmerColors.contents = Self.stripe(colors)
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

    /// The tints across a strip, a pixel tall and a few hundred wide (they're soft; it's stretched).
    private static func stripe(_ colors: [CGColor]) -> CGImage? {
        let width = 512
        guard let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                        locations: nil) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        return context.makeImage()
    }

    // MARK: Drawing

    func begin(at point: CGPoint) {
        reset()
        withoutAnimation { shimmer.isHidden = look.shimmer <= 0 }
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
            extent = .null
            cover(.zero)
            shimmer.isHidden = true
        }
        removeAllAnimations()
        points = []
        committed = 0
    }

    /// Grows the groups and the shimmer to cover `rect` too. Their coordinates stay the display's
    /// (bounds origin = where they sit), so nothing inside moves.
    private func cover(_ rect: CGRect) {
        let grown = extent.isNull ? rect : extent.union(rect)
        guard grown != extent else { return }
        extent = grown
        for layer in glowGroups + [core, shimmer, shimmerMask] {
            layer.bounds = grown
            layer.position = CGPoint(x: grown.midX, y: grown.midY)
        }
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
        cover(box)
        shape.frame = box
        var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        shape.path = path.copy(using: &shift)
    }

    // MARK: Release

    /// The stroke morphs into a rounded rectangle around `rect` (thinner, as an outline).
    /// Without motion the outline just appears.
    ///
    /// Kept cheap for the render server, which re-strokes an animated path every frame: only the
    /// core and the nearest glow morph, along at most `morphPoints` points; the wider glows and
    /// the shimmer go straight to the outline (drawn once) and fade in as the morph lands. The
    /// drawn stroke itself (full detail) fades out over the morph's first moments, so starting
    /// from a simplified copy of it never shows as a jump.
    func morph(into rect: CGRect, duration: Double, animated: Bool) {
        let length = StrokeGeometry.length(points)
        let radius = min(look.selectionRadius, rect.width / 2, rect.height / 2)
        let perimeter = StrokeGeometry.perimeter(rect, radius: radius)
        let count = min(max(Int(max(length, perimeter) / 4), 120), Self.morphPoints)
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

    /// Every chunk replaced by one full-display shape per tier, showing `to`; with `from`, the core
    /// and the first glow morph there (the core thinning to the outline's width) while the drawn
    /// stroke fades out, and the other tiers fade in as it lands.
    private func showOutline(from: CGPath?, to: CGPath, duration: Double) {
        let residue = CALayer()
        withoutAnimation {
            residue.bounds = extent
            residue.position = CGPoint(x: extent.midX, y: extent.midY)
            for parent in tierParents {
                let copy = CALayer()
                copy.bounds = extent
                copy.position = residue.position
                copy.allowsGroupOpacity = true
                copy.opacity = parent === shimmerMask ? 0 : parent.opacity
                for chunk in parent.sublayers ?? [] {
                    chunk.removeFromSuperlayer()
                    if from != nil { copy.addSublayer(chunk) }
                }
                residue.addSublayer(copy)
            }
            if from != nil { addSublayer(residue) }
            let widest = look.glowWidths.max() ?? look.strokeWidth
            cover(to.boundingBoxOfPath.insetBy(dx: -widest, dy: -widest))
            if let from { cover(from.boundingBoxOfPath.insetBy(dx: -widest, dy: -widest)) }
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
        let morphing = [live[0], live[live.count - 1]]
        for shape in morphing {
            let morph = CABasicAnimation(keyPath: "path")
            morph.fromValue = from
            morph.toValue = to
            morph.duration = duration
            morph.timingFunction = timing
            shape.add(morph, forKey: "morph")
        }
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = look.strokeWidth
        thin.toValue = look.outlineWidth
        thin.duration = duration
        thin.timingFunction = timing
        live[live.count - 1].add(thin, forKey: "thin")
        // The rest of the outline arrives with the morph's landing.
        let now = CACurrentMediaTime()
        for shape in live where !morphing.contains(where: { $0 === shape }) {
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = shape.convertTime(now + duration * 0.6, from: nil)
            appear.duration = duration * 0.5
            appear.fillMode = .backwards
            shape.add(appear, forKey: "appear")
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { residue.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = min(0.14, duration * 0.5)
        withoutAnimation { residue.opacity = 0 }
        residue.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
