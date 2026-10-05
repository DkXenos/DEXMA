import AppKit
import SwiftUI

/// Capture mode on one display: the frozen screen (dimmed), the edge glow, the hint, the stroke
/// the user draws, then the lifted selection flying into the notch. Every animation here is Core
/// Animation's (the render server runs it): the main thread only adds points while drawing.
/// Coordinates are the display's points, top-left origin (the view is flipped, the layers'
/// geometry too).
final class CaptureOverlayView: NSView {
    /// A press started a stroke.
    var onStrokeBegan: (() -> Void)?
    /// The press ended: the stroke's points (a click: one or a few close together).
    var onStrokeEnded: (([CGPoint]) -> Void)?
    /// Strokes are taken (off once one has ended, until the next capture).
    var acceptsStrokes = false

    private let canvas = CaptureCanvasView()
    private let root = CALayer()
    private let frozen = CALayer()
    private let dim = CALayer()
    private let glow = EdgeGlowLayer()
    private let lift = CALayer()
    private let liftImage = CALayer()
    private let stroke = StrokeLayer()
    private let hint = NSHostingView(rootView: CaptureHintView())
    private var look = CaptureLook.full
    private var animated = true
    private var image: CGImage?
    private var drawing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Layer-hosting: these layers are ours alone, laid out top-left like the view (the canvas
        // is flipped).
        canvas.layer = root
        canvas.wantsLayer = true
        frozen.contentsGravity = .resize
        dim.backgroundColor = CGColor(gray: 0, alpha: 1)
        liftImage.masksToBounds = true
        liftImage.contentsGravity = .resize
        lift.addSublayer(liftImage)
        lift.shadowColor = CGColor(gray: 0, alpha: 1)
        for layer in [frozen, dim, glow, lift, stroke] { root.addSublayer(layer) }
        addSubview(canvas)
        hint.sizingOptions = []
        hint.wantsLayer = true
        addSubview(hint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Every click and drag is the overlay's (the hint is only a picture).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: Showing

    /// Before each capture, while the window is still off screen: a clean slate at `size`
    /// (points; `scale` pixels per point), the look, whether things may move, and how far down
    /// the hint goes.
    func prepare(size: CGSize, scale: CGFloat, look: CaptureLook, animated: Bool, hintTop: CGFloat) {
        self.look = look
        self.animated = animated
        image = nil
        drawing = false
        acceptsStrokes = true
        canvas.frame = CGRect(origin: .zero, size: size)
        withoutAnimation {
            root.removeAllAnimations()
            root.opacity = 1
            root.contentsScale = scale
            for layer in [frozen, dim, lift] {
                layer.removeAllAnimations()
                layer.frame = CGRect(origin: .zero, size: size)
            }
            frozen.contents = nil
            frozen.opacity = 0
            dim.opacity = 0
            lift.isHidden = true
            lift.transform = CATransform3DIdentity
            liftImage.contents = nil
            glow.removeAllAnimations()
            glow.opacity = 0
        }
        glow.configure(size: size, look: look, animated: animated)
        stroke.configure(look: look, size: size, scale: scale, animated: animated)
        let hintSize = hint.fittingSize
        hint.frame = CGRect(x: ((size.width - hintSize.width) / 2).rounded(), y: hintTop,
                            width: hintSize.width, height: hintSize.height)
        hint.layer?.removeAllAnimations()
        hint.layer?.opacity = 0
    }

    /// The window just came on screen: the glow and the hint fade in (the frozen screen follows
    /// when it's there).
    func appear() {
        fade(glow, to: 1, duration: look.fadeIn)
        if let layer = hint.layer { fade(layer, to: 1, duration: look.fadeIn) }
    }

    /// The frozen screen arrived: it fades in over the live one (they match, so only anything
    /// that was moving settles), then dims.
    func showFrozen(_ image: CGImage) {
        self.image = image
        withoutAnimation { frozen.contents = image }
        fade(frozen, to: 1, duration: animated ? 0.08 : 0)
        fade(dim, to: Float(look.dim), duration: look.fadeIn)
    }

    // MARK: Drawing

    override func mouseDown(with event: NSEvent) {
        guard acceptsStrokes else { return }
        drawing = true
        NSCursor.crosshair.set()
        stroke.begin(at: location(of: event))
        if let layer = hint.layer, layer.opacity > 0 { fade(layer, to: 0, duration: 0.15) }
        onStrokeBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard drawing else { return }
        NSCursor.crosshair.set()
        stroke.add(location(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard drawing else { return }
        drawing = false
        acceptsStrokes = false
        stroke.add(location(of: event))
        onStrokeEnded?(stroke.points)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .cursorUpdate, .mouseMoved, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// The pointer in the display's points, kept on this display (a stroke can't leave it).
    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    // MARK: Selecting

    /// The stroke (or, for a click, a fresh outline) settles into a rounded rectangle around
    /// `rect`; then the selection lifts (the rest dims further). `completion` once it rests.
    func select(_ rect: CGRect, fromStroke: Bool, completion: @escaping () -> Void) {
        let morph = animated ? look.morph : 0
        if fromStroke {
            stroke.morph(into: rect, duration: morph, animated: animated)
        } else {
            stroke.outline(rect, duration: morph, animated: animated)
        }
        let radius = min(look.selectionRadius, rect.width / 2, rect.height / 2)
        withoutAnimation {
            lift.frame = rect
            lift.shadowPath = CGPath(roundedRect: lift.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            lift.shadowRadius = look.liftShadowRadius
            lift.shadowOffset = CGSize(width: 0, height: 8)
            lift.shadowOpacity = 0
            liftImage.frame = lift.bounds
            liftImage.cornerRadius = radius
            liftImage.contents = image
            liftImage.contentsRect = CGRect(x: rect.minX / bounds.width, y: rect.minY / bounds.height,
                                            width: rect.width / bounds.width, height: rect.height / bounds.height)
            lift.opacity = 0
            lift.isHidden = false
        }
        let begin = CACurrentMediaTime() + morph * 0.5
        let duration = animated ? look.morph * 0.7 : 0
        fade(dim, to: Float(look.selectedDim), duration: duration, begin: begin)
        fade(lift, to: 1, duration: duration, begin: begin)
        if animated {
            let scale = NSValue(caTransform3D: CATransform3DMakeScale(look.lift, look.lift, 1))
            animate(lift, "transform", to: scale, duration: duration, begin: begin)
            animate(lift, "shadowOpacity", to: Float(look.liftShadowOpacity), duration: duration, begin: begin)
            let about = Self.scale(look.lift, about: CGPoint(x: rect.midX, y: rect.midY), in: stroke)
            animate(stroke, "transform", to: NSValue(caTransform3D: about), duration: duration, begin: begin)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + morph * 0.5 + duration + (animated ? look.hold : 0), execute: completion)
    }

    // MARK: Leaving

    /// The lifted selection flies to `target` (the notch's centre) and shrinks into it, stretching
    /// like a drop being pulled in; everything else fades, uncovering the live screen. `arriving`
    /// fires a moment before it gets there (time to start opening the notch), `completion` when
    /// it's gone.
    func fly(to target: CGPoint, arriving: @escaping () -> Void, completion: @escaping () -> Void) {
        let duration = look.flight
        for layer in [frozen, dim, glow, stroke] { fade(layer, to: 0, duration: look.fadeOut) }
        if let layer = hint.layer { fade(layer, to: 0, duration: 0.1) }

        let start = CGPoint(x: lift.frame.midX, y: lift.frame.midY)
        let size = lift.bounds.size
        // Down to a drop about 24 pt across, a little taller than wide as it's sucked up.
        let end = 24 / max(size.width, size.height, 1)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: target, control: CGPoint(x: lerp(start.x, target.x, 0.2), y: lerp(start.y, target.y, 0.75)))
        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path
        let transform = CAKeyframeAnimation(keyPath: "transform")
        let mid = lerp(look.lift, end, 0.45)
        transform.values = [CATransform3DMakeScale(look.lift, look.lift, 1), CATransform3DMakeScale(mid * 0.92, mid * 1.1, 1),
                            CATransform3DMakeScale(end * 0.7, end * 1.4, 1)].map { NSValue(caTransform3D: $0) }
        transform.keyTimes = [0, 0.55, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, 0.82, 1]
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = lift.shadowOpacity
        shadow.toValue = 0
        shadow.duration = duration * 0.5
        let group = CAAnimationGroup()
        group.animations = [position, transform, opacity, shadow]
        group.duration = duration
        // Pulled in: slow to leave, quicker and quicker toward the notch.
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.85, 0.45)
        let round = CABasicAnimation(keyPath: "cornerRadius")
        round.fromValue = liftImage.cornerRadius
        round.toValue = min(size.width, size.height) / 2
        round.duration = duration
        round.timingFunction = group.timingFunction

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        withoutAnimation {
            lift.position = target
            lift.transform = CATransform3DMakeScale(end * 0.7, end * 1.4, 1)
            lift.opacity = 0
            lift.shadowOpacity = 0
            liftImage.cornerRadius = min(size.width, size.height) / 2
        }
        lift.add(group, forKey: "flight")
        liftImage.add(round, forKey: "round")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8, execute: arriving)
    }

    /// The lifted selection flies onto `chip` (display points: the floating glass field's chip,
    /// which shows the same picture) and shrinks to fit inside it, rounding to its corners, then
    /// fades into it; everything else fades. `arriving` a moment before it lands (time for the
    /// glass to appear), `completion` when it's gone.
    func fly(into chip: CGRect, cornerRadius: CGFloat, arriving: @escaping () -> Void,
             completion: @escaping () -> Void) {
        let duration = look.flight
        for layer in [frozen, dim, glow, stroke] { fade(layer, to: 0, duration: look.fadeOut) }
        if let layer = hint.layer { fade(layer, to: 0, duration: 0.1) }

        let start = CGPoint(x: lift.frame.midX, y: lift.frame.midY)
        let target = CGPoint(x: chip.midX, y: chip.midY)
        let size = lift.bounds.size
        // Fitted inside the chip (the chip fills its square with the same picture).
        let end = min(chip.width / max(size.width, 1), chip.height / max(size.height, 1))
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: target, control: CGPoint(x: lerp(start.x, target.x, 0.3), y: lerp(start.y, target.y, 0.85)))
        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(look.lift, look.lift, 1))
        transform.toValue = NSValue(caTransform3D: CATransform3DMakeScale(end, end, 1))
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, 0.88, 1]
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = lift.shadowOpacity
        shadow.toValue = 0
        shadow.duration = duration * 0.6
        let group = CAAnimationGroup()
        group.animations = [position, transform, opacity, shadow]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
        // The corners end as the chip's (in the layer's own, unscaled, points).
        let finalRadius = cornerRadius / max(end, 0.001)
        let round = CABasicAnimation(keyPath: "cornerRadius")
        round.fromValue = liftImage.cornerRadius
        round.toValue = finalRadius
        round.duration = duration
        round.timingFunction = group.timingFunction

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        withoutAnimation {
            lift.position = target
            lift.transform = CATransform3DMakeScale(end, end, 1)
            lift.opacity = 0
            lift.shadowOpacity = 0
            liftImage.cornerRadius = finalRadius
        }
        lift.add(group, forKey: "flight")
        liftImage.add(round, forKey: "round")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6, execute: arriving)
    }

    /// Everything fades away (cancel, or Reduce Motion's hand-off), then `completion`.
    func fadeAway(duration: Double, completion: @escaping () -> Void) {
        acceptsStrokes = false
        drawing = false
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        fade(root, to: 0, duration: duration)
        if let layer = hint.layer { fade(layer, to: 0, duration: duration) }
        CATransaction.commit()
    }

    /// Off screen: let go of the frozen picture (tens of MB).
    func clear() {
        image = nil
        withoutAnimation {
            frozen.contents = nil
            liftImage.contents = nil
        }
        stroke.reset()
    }

    // MARK: Animation helpers

    private func fade(_ layer: CALayer, to value: Float, duration: Double, begin: CFTimeInterval = 0) {
        animate(layer, "opacity", to: value, duration: duration, begin: begin)
    }

    /// Sets `keyPath` to `value` and animates there from what's on screen now (Core Animation runs
    /// it). Starting later (`begin`): it holds the old value until then.
    private func animate(_ layer: CALayer, _ keyPath: String, to value: Any, duration: Double, begin: CFTimeInterval = 0) {
        let from = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        withoutAnimation { layer.setValue(value, forKeyPath: keyPath) }
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if begin > 0 {
            animation.beginTime = layer.convertTime(begin, from: nil)
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: keyPath)
    }

    /// Scaling `layer` by `factor` about `point` (in its superlayer's coordinates).
    private static func scale(_ factor: CGFloat, about point: CGPoint, in layer: CALayer) -> CATransform3D {
        let dx = point.x - layer.position.x, dy = point.y - layer.position.y
        let moved = CATransform3DMakeTranslation(dx, dy, 0)
        return CATransform3DTranslate(CATransform3DScale(moved, factor, factor, 1), -dx, -dy, 0)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
