import AppKit

/// Bends the real screen around the notch, the way the screen warps around the iPhone's
/// Camera Control: while the notch moves (pushing space out as it grows, pulling it in as it
/// shrinks), around the pointer as it comes near the notch, and — resting — around the swollen
/// (peek) notch and the open panel for as long as they stay.
///
/// With Screen Recording allowed, ScreenCaptureKit streams the screen under the panel and
/// `ScreenWarpView` redraws it bent and colour-split. The stream runs only around intent
/// (pointer nearby, fingers on the trackpad's top edge, an open or close) and while the notch
/// is swollen or open (the user's choice: macOS's recording indicator shows meanwhile), and
/// stops 1.5 s after things go quiet. At rest the warp is redrawn only when the stream
/// delivers a new frame (the screen behind changed), not every display frame. Without the permission, the Liquid Glass ring (`BackdropLens`,
/// macOS 26) bends the edge during motion instead.
final class ScreenBender {
    /// The Settings switch; the warp also needs the permission.
    var isWarpEnabled = true {
        didSet {
            if !isWarpEnabled { stopCapture() }
            if isWarpEnabled != oldValue { stoppedByUser = false }
        }
    }
    var tuning = EffectTuning.full
    /// Whether the pointer lens may show (not while the terminal is open).
    var allowsPointer: () -> Bool = { true }
    /// Starts the display link if it's resting, so `step` gets called.
    var wake: () -> Void = {}

    private let panel: NSPanel
    private let geometry: () -> NotchGeometry
    private let capture = ScreenCapture()
    private let warpView: ScreenWarpView
    private let glass: BackdropLens
    /// Cached: asking TCC takes ~10 ms, far too long for the main thread at a motion's start.
    private var permitted = false
    private var permissionCheckPending = false
    /// The user stopped capture from macOS's recording indicator: respect that until DEXMA
    /// restarts or the Settings switch is turned off and on (the glass edge stands in).
    private var stoppedByUser = false
    private var lastActivity: CFTimeInterval = 0
    private var stopCheckPending = false
    /// Fades the warp in once the first captured frame is there, so it never pops on.
    private var warpBlend: CGFloat = 0
    private var pointerTarget: CGFloat = 0
    private var pointerStrength: CGFloat = 0
    private var pointerPoint = CGPoint.zero
    private var pointerGoal = CGPoint.zero
    /// The resting push of the last frame (pt): while above zero the stream keeps running.
    private var restingAmount: CGFloat = 0
    /// What the last frame drew, for redrawing it when a new screen frame arrives at rest.
    private var lastUniforms: WarpUniforms?
    private var lastStepTime: CFTimeInterval = 0
    private var lastRestRender: CFTimeInterval = 0
    private var restRedrawPending = false
    private var restingSilhouetteRect: CGRect?
    private var restingRadius: CGFloat = 0

    init(panel: NSPanel, container: NSView, geometry: @escaping () -> NotchGeometry) {
        self.panel = panel
        self.geometry = geometry
        glass = BackdropLens(in: container)
        warpView = ScreenWarpView(frame: container.bounds)
        warpView.autoresizingMask = [.width, .height]
        container.addSubview(warpView, positioned: .below, relativeTo: nil)
        capture.onUserStopped = { [weak self] in
            self?.stoppedByUser = true
            self?.warpView.hide()
        }
        capture.onNewFrame = { [weak self] in self?.redrawAtRest() }
        refreshPermission()
    }

    /// Re-checks Screen Recording off the main thread; the answer applies from the next motion.
    func refreshPermission() {
        guard !permissionCheckPending else { return }
        permissionCheckPending = true
        DispatchQueue.global(qos: .utility).async {
            let granted = CGPreflightScreenCaptureAccess()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.permissionCheckPending = false
                if self.permitted != granted {
                    self.permitted = granted
                    if !granted { self.stopCapture() }
                }
            }
        }
    }

    /// Screen Recording is allowed and the switch is on: the real warp can run.
    var canWarp: Bool { isWarpEnabled && permitted && !stoppedByUser && warpView.isUsable }

    // MARK: Intent

    /// Something is about to move (or the pointer is near): get the stream going now, so its
    /// frames are there by the time the motion needs them.
    func prepare() {
        refreshPermission()
        guard canWarp, let screen = panel.screen else { return }
        noteActivity()
        capture.start(rect: panel.frame, on: screen)
    }

    /// From the hover monitor (global AppKit coordinates).
    func pointerMoved(to point: NSPoint) {
        let notch = geometry().notchRect
        let dx = max(notch.minX - point.x, 0, point.x - notch.maxX)
        let dy = max(notch.minY - point.y, 0)
        let distance = (dx * dx + dy * dy).squareRoot()
        let reach = max(tuning.hoverReach, 1)
        let closeness = 1 - smoothstep(distance / reach)
        let target = allowsPointer() && canWarp && tuning.hoverLens > 0 ? closeness : 0
        let frame = panel.frame
        pointerGoal = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        if pointerStrength == 0 { pointerPoint = pointerGoal }
        guard target != pointerTarget else { return }
        pointerTarget = target
        if target > 0 { prepare() }
        wake()
    }

    // MARK: Per frame

    /// Once per display frame (and with `motion == nil` once motion ends). Returns true while
    /// the pointer lens still needs frames.
    func step(dt: CFTimeInterval, motion: SilhouetteMotion?) -> Bool {
        lastStepTime = CACurrentMediaTime()
        capture.setFrameRate(120)  // Moving: every display frame.
        let pointerBusy = stepPointer(dt)
        restingAmount = motion?.restingPush ?? 0
        let pushing = (motion?.strength ?? 0) * (motion?.direction ?? 0) * tuning.screenWarp
            + restingAmount + tuning.hoverPush * pointerStrength
        let lens = tuning.hoverLens * pointerStrength
        #if DEBUG
        let wantsWarp = canWarp && (abs(pushing) > 0.01 || lens > 0.001 || debugFullCoverage)
        #else
        let wantsWarp = canWarp && (abs(pushing) > 0.01 || lens > 0.001)
        #endif

        restingSilhouetteRect = motion?.silhouette
        restingRadius = motion?.radius ?? 0
        if wantsWarp, let frame = capture.latestFrame() {
            noteActivity()
            warpBlend = min(warpBlend + CGFloat(dt) / 0.08, 1)
            #if DEBUG
            if debugFullCoverage || debugPosing { warpBlend = 1 }
            #endif
            let reach = tuning.screenWarpReach
            let silhouette = motion?.silhouette ?? restingSilhouette()
            let radius = motion?.radius ?? geometry().shape(at: 0).drawnBottomRadius
            var uniforms = WarpUniforms()
            let size = panel.frame.size
            uniforms.size = SIMD2(Float(size.width), Float(size.height))
            // Pulling in more than half the reach would fold the image over itself.
            uniforms.amount = Float(min(max(pushing, -0.45 * reach), reach) * warpBlend)
            uniforms.body = SIMD4(Float(silhouette.midX), Float(silhouette.width),
                                  Float(silhouette.height), Float(radius))
            uniforms.pointer = SIMD4(Float(pointerPoint.x), Float(pointerPoint.y),
                                     Float(lens * warpBlend), Float(tuning.hoverLensRadius))
            uniforms.reach = Float(reach)
            uniforms.chroma = Float(tuning.screenChroma)
            #if DEBUG
            uniforms.debug.x = debugFullCoverage ? 1 : 0
            #endif
            warpView.render(frame, uniforms: uniforms, colorSpace: panel.screen?.colorSpace?.cgColorSpace)
            lastUniforms = uniforms
            glass.update(silhouette: .zero, radius: 0, ring: 0)
        } else {
            if wantsWarp {
                noteActivity()  // Waiting for the stream's first frame.
                // At rest no more display frames come: the first stream frame draws it.
                if restingAmount > 0 { prepare() }
            } else {
                warpBlend = 0
            }
            lastUniforms = nil
            warpView.hide()
            updateGlass(motion)
        }
        return pointerBusy
    }

    /// A new screen frame arrived. While the display link is resting (the notch swollen or
    /// open and still), redraw the resting warp over it, with the stream slowed to
    /// `restingWarpRate` (a thin bent band; a busy screen behind, e.g. a video, would otherwise
    /// cost a capture and a draw per display frame); a change arriving sooner is drawn when the
    /// interval ends. While the link runs, `step` draws.
    private func redrawAtRest() {
        #if DEBUG
        if debugSkipRestRedraw { return }
        #endif
        let now = CACurrentMediaTime()
        guard restingAmount > 0, canWarp, now - lastStepTime > 0.03 else { return }
        let rate = max(tuning.restingWarpRate, 1)
        capture.setFrameRate(rate)
        let interval = 1.0 / CFTimeInterval(rate)
        guard now - lastRestRender >= interval - 0.001 else {
            guard !restRedrawPending else { return }
            restRedrawPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (lastRestRender + interval - now)) { [weak self] in
                self?.restRedrawPending = false
                self?.redrawAtRest()
            }
            return
        }
        guard let frame = capture.latestFrame() else { return }
        lastRestRender = now
        noteActivity()
        var uniforms: WarpUniforms
        if let lastUniforms {
            uniforms = lastUniforms
        } else {
            // The stream wasn't there yet at the last frame: start from the resting warp (no
            // pointer lens), fading in over the next few screen frames.
            warpBlend = 0
            uniforms = restingUniforms()
        }
        if warpBlend < 1 {
            warpBlend = min(warpBlend + 0.25, 1)
            let full = restingUniforms()
            uniforms.amount = full.amount * Float(warpBlend)
        }
        warpView.render(frame, uniforms: uniforms, colorSpace: panel.screen?.colorSpace?.cgColorSpace,
                        synchronized: false)
        lastUniforms = uniforms
    }

    /// The resting warp around the silhouette at the panel's current size, no pointer lens.
    private func restingUniforms() -> WarpUniforms {
        let silhouette = restingSilhouetteRect ?? restingSilhouette()
        var uniforms = WarpUniforms()
        let size = panel.frame.size
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        uniforms.amount = Float(min(restingAmount, tuning.screenWarpReach))
        uniforms.body = SIMD4(Float(silhouette.midX), Float(silhouette.width), Float(silhouette.height),
                              Float(restingRadius))
        uniforms.reach = Float(tuning.screenWarpReach)
        uniforms.chroma = Float(tuning.screenChroma)
        return uniforms
    }

    /// Launch: compiles nothing new (the warp pipeline is built in `ScreenWarpView.init`), but
    /// has the window server build the glass once, behind the closed notch.
    func warmUp() {
        glass.warmUp(behind: restingSilhouette())
    }

    // MARK: Private

    /// Without the warp (no permission, or the switch off): the glass ring during motion.
    private func updateGlass(_ motion: SilhouetteMotion?) {
        guard let motion, !canWarp else {
            glass.update(silhouette: .zero, radius: 0, ring: 0)
            return
        }
        // Never past the window's edge, or it gets cut off in a straight line.
        let panelSize = panel.frame.size
        let room = min(motion.silhouette.minX, panelSize.width - motion.silhouette.maxX,
                       panelSize.height - motion.silhouette.maxY) - 1
        let ring = min(tuning.backdropRing * motion.strength, max(room, 0))
        glass.update(silhouette: motion.silhouette, radius: motion.radius, ring: ring)
    }

    private func stepPointer(_ dt: CFTimeInterval) -> Bool {
        if !allowsPointer() { pointerTarget = 0 }
        let rate = CGFloat(1 - exp(-dt / 0.09))
        pointerStrength += (pointerTarget - pointerStrength) * rate
        if pointerTarget == 0, pointerStrength < 0.003 { pointerStrength = 0 }
        let follow = CGFloat(1 - exp(-dt / 0.035))
        pointerPoint.x += (pointerGoal.x - pointerPoint.x) * follow
        pointerPoint.y += (pointerGoal.y - pointerPoint.y) * follow
        return pointerTarget > 0 || pointerStrength > 0
    }

    private func restingSilhouette() -> CGRect {
        let shape = geometry().shape(at: 0)
        return CGRect(x: shape.centerX - shape.width / 2, y: 0, width: shape.width, height: shape.height)
    }

    private func noteActivity() {
        lastActivity = CACurrentMediaTime()
        scheduleStopCheck()
    }

    /// Stops the stream (and macOS's recording indicator) once nothing has needed it for a
    /// moment.
    private func scheduleStopCheck() {
        guard !stopCheckPending else { return }
        stopCheckPending = true
        let idle: CFTimeInterval = 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + idle) { [weak self] in
            guard let self else { return }
            self.stopCheckPending = false
            if CACurrentMediaTime() - self.lastActivity >= idle - 0.01, self.pointerTarget == 0,
               self.restingAmount == 0 {
                self.stopCapture()
            } else {
                self.scheduleStopCheck()
            }
        }
    }

    private func stopCapture() {
        capture.stop()
        warpView.hide()
        warpBlend = 0
        lastUniforms = nil
    }

    #if DEBUG
    /// Keeps capture running (as if something needed it) — for measuring its cost.
    func debugKeepCapturing() {
        prepare()
        noteActivity()
    }

    var debugFullCoverage = false
    var debugSkipRestRedraw = false

    /// Posed frames draw at full strength straight away.
    var debugPosing = false
    var debugCapture: ScreenCapture { capture }
    var debugPermitted: Bool { permitted }
    var debugGlassShowing: Bool { glass.isShowing }
    var debugWarpShowing: Bool { !warpView.isHidden }
    var debugRestingAmount: CGFloat { restingAmount }
    #endif
}
