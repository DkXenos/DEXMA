import AppKit
import CoreVideo
import Metal
import QuartzCore

/// Draws the captured screen under the panel, bent around the notch and the pointer
/// (ScreenWarp.metal). Lives below the black silhouette in `PanelContentView`; hidden — so not
/// composited at all — whenever there's nothing to bend.
///
/// While the silhouette moves, presented inside the current Core Animation transaction, so each
/// warp frame lands on screen together with the SwiftUI silhouette it was computed for. At rest
/// (the silhouette still) it's presented on its own, without blocking the main thread.
final class ScreenWarpView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private var textureGeneration = -1

    override init(frame: CGRect) {
        commandQueue = device?.makeCommandQueue()
        pipeline = Self.makePipeline(device)
        super.init(frame: frame)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.presentsWithTransaction = true
        metalLayer.maximumDrawableCount = 3
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var isUsable: Bool { pipeline != nil && commandQueue != nil }

    /// Draws one frame. Returns false (and draws nothing) if there's no capture frame yet.
    /// `synchronized`: in step with the current CA transaction (the silhouette is moving).
    @discardableResult
    func render(_ frame: (buffer: CVPixelBuffer, generation: Int), uniforms: WarpUniforms,
                colorSpace: CGColorSpace?, synchronized: Bool = true) -> Bool {
        guard let device, let commandQueue, let pipeline, bounds.width > 0 else { return false }
        if frame.generation != textureGeneration || texture == nil {
            guard let surface = CVPixelBufferGetIOSurface(frame.buffer)?.takeUnretainedValue() else { return false }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: IOSurfaceGetWidth(surface),
                height: IOSurfaceGetHeight(surface), mipmapped: false)
            descriptor.usage = .shaderRead
            guard let made = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else { return false }
            texture = made
            textureGeneration = frame.generation
        }
        let scale = window?.backingScaleFactor ?? 2
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if metalLayer.drawableSize != drawableSize { metalLayer.drawableSize = drawableSize }
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        if let colorSpace, metalLayer.colorspace !== colorSpace { metalLayer.colorspace = colorSpace }
        if metalLayer.presentsWithTransaction != synchronized { metalLayer.presentsWithTransaction = synchronized }
        if isHidden { isHidden = false }
        CATransaction.commit()

        guard let drawable = metalLayer.nextDrawable(),
              let commands = commandQueue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
        var values = uniforms
        values.scale = Float(scale)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&values, length: MemoryLayout<WarpUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if synchronized {
            // With presentsWithTransaction the drawable is shown in the current CA transaction:
            // schedule the GPU work first, then present.
            commands.commit()
            commands.waitUntilScheduled()
            drawable.present()
        } else {
            commands.present(drawable)
            commands.commit()
        }
        return true
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        texture = nil  // Lets ScreenCaptureKit reuse the surface.
        textureGeneration = -1
    }

    private static func makePipeline(_ device: MTLDevice?) -> MTLRenderPipelineState? {
        guard let device, let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "warpVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "warpFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
