import Metal
import SwiftUI

/// Renders the effect to images, off screen: for exports, thumbnails and tests.
///
/// ```swift
/// let renderer = try GlassGlowRenderer()
/// let image = renderer.image(of: Image(systemName: "heart.fill").font(.system(size: 200)),
///                            size: CGSize(width: 240, height: 220), time: 2)
/// ```
@MainActor
public final class GlassGlowRenderer {
    private let canvas: GlowCanvas

    public init() throws {
        guard let pipelines = GlowPipelines.shared else { throw GlassGlowError.metalUnavailable }
        canvas = try GlowCanvas(pipelines: pipelines)
    }

    /// The room left around content of `size` (in points) for the halo, on every side.
    public nonisolated static func margin(for size: CGSize) -> CGFloat {
        (size.height * 0.45).rounded()
    }

    /// Renders `content`, laid out at `size` points, as glass at `time` seconds.
    ///
    /// The shape is the content's alpha. The image is `size` plus `margin(for: size)` on every side,
    /// at `scale` pixels per point, with premultiplied alpha: the light over transparency.
    public func image<Content: View>(of content: Content, size: CGSize, scale: CGFloat = 2, style: GlassGlowStyle = .default, time: Double = 0) -> CGImage? {
        guard let mask = MaskSnapshot.image(content, size: size, margin: Self.margin(for: size), scale: scale, environment: nil) else { return nil }
        return image(mask: mask, style: style, time: time)
    }

    /// Renders the shape in `mask` (its alpha) as glass at `time` seconds. The image has the mask's
    /// size, so leave room around the shape for the halo.
    public func image(mask: CGImage, style: GlassGlowStyle = .default, time: Double = 0) -> CGImage? {
        render(mask: mask, style: style.resolved(in: EnvironmentValues()), phase: Float(time * style.speed))
    }

    func render(mask: CGImage, style: ResolvedStyle, phase: Float) -> CGImage? {
        canvas.setMask(mask)
        let device = canvas.pipelines.device
        let w = canvas.width, h = canvas.height
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        guard let target = device.makeTexture(descriptor: d),
              let buffer = device.makeBuffer(length: w * h * 4, options: [.storageModeShared]),
              let commandBuffer = canvas.pipelines.queue.makeCommandBuffer() else { return nil }
        // The bloom picks its mip levels from the shape's size, measured on the GPU: on a new mask
        // the first frame only measures it.
        if canvas.needsMeasuring {
            canvas.encode(into: target, commandBuffer: commandBuffer, time: phase, style: style)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return render(mask: mask, style: style, phase: phase)
        }
        canvas.encode(into: target, commandBuffer: commandBuffer, time: phase, style: style)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let data = Data(bytes: buffer.contents(), count: w * h * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The alpha of a SwiftUI view, drawn with a margin around it.
enum MaskSnapshot {
    @MainActor
    static func image<Content: View>(_ content: Content, size: CGSize, margin: CGFloat, scale: CGFloat, environment: EnvironmentValues?) -> CGImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let canvas = CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
        let view = content
            .frame(width: size.width, height: size.height)
            .padding(margin)
            .transformEnvironment(\.self) { if let environment { $0 = environment } }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(canvas)
        return renderer.cgImage
    }
}
