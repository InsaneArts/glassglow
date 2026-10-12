import MetalKit
import SwiftUI

/// The live effect: an `MTKView` that redraws the glass every frame.
struct GlowSurface<Content: View> {
    let content: Content
    let size: CGSize
    let margin: CGFloat
    let scale: CGFloat
    let style: GlassGlowStyle
    let time: Double?
    let environment: EnvironmentValues

    func makeCoordinator() -> GlowDriver { GlowDriver() }

    private func makeView(_ driver: GlowDriver) -> MTKView {
        let view = MTKView(frame: .zero, device: GlowPipelines.shared?.device)
        view.delegate = driver
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        #if os(macOS)
        view.layer?.isOpaque = false
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        #endif
        return view
    }

    @MainActor
    private func update(_ view: MTKView, _ driver: GlowDriver) {
        if let mask = MaskSnapshot.image(content, size: size, margin: margin, scale: scale, environment: environment) {
            driver.setMask(mask)
            view.drawableSize = CGSize(width: mask.width, height: mask.height)
        }
        driver.style = style.resolved(in: environment)
        driver.speed = style.speed
        driver.fixedTime = time
        if time == nil {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        } else {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            #if os(macOS)
            view.needsDisplay = true
            #else
            view.setNeedsDisplay()
            #endif
        }
    }
}

#if os(macOS)
extension GlowSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeView(context.coordinator) }
    func updateNSView(_ view: MTKView, context: Context) { update(view, context.coordinator) }
}
#else
extension GlowSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeView(context.coordinator) }
    func updateUIView(_ view: MTKView, context: Context) { update(view, context.coordinator) }
}
#endif

/// Draws one surface: owns its canvas and the animation clock.
final class GlowDriver: NSObject, MTKViewDelegate {
    private let canvas = GlowPipelines.shared.flatMap { try? GlowCanvas(pipelines: $0) }
    var style = GlassGlowStyle.default.resolved(in: EnvironmentValues())
    var speed: Double = 1
    var fixedTime: Double?
    private var clock: Double = 0
    private var lastFrame: CFTimeInterval?

    func setMask(_ image: CGImage) {
        canvas?.setMask(image)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        // Advance by the frame time, capped so a stall or a hidden window does not jump the loop.
        if let lastFrame { clock += min(now - lastFrame, 0.1) * speed }
        lastFrame = now
        guard let canvas, canvas.hasMask,
              let drawable = view.currentDrawable,
              drawable.texture.width == canvas.width, drawable.texture.height == canvas.height,
              let commandBuffer = canvas.pipelines.queue.makeCommandBuffer() else { return }
        let phase = fixedTime.map { $0 * speed } ?? clock
        canvas.encode(into: drawable.texture, commandBuffer: commandBuffer, time: Float(phase.truncatingRemainder(dividingBy: GlassGlowStyle.loopDuration)), style: style)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
