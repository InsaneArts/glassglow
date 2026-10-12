import CoreGraphics
import Foundation
import Metal
import simd

/// The compiled kernels, shared by every canvas on the device.
final class GlowPipelines {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let reset, seed, flood, distance, smooth, shade, blur, compose: MTLComputePipelineState
    /// A black 1x1 texture for unused bloom slots.
    let black: MTLTexture

    /// The shared pipelines on the default device, or nil without Metal.
    static let shared: GlowPipelines? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try? GlowPipelines(device: device)
    }()

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let url = Bundle.module.url(forResource: "GlassGlow", withExtension: "metal", subdirectory: "Shaders") else {
            throw GlassGlowError.metalUnavailable
        }
        self.queue = queue
        // Compiled at run time: SwiftPM only compiles .metal files in Xcode builds.
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else { throw GlassGlowError.metalUnavailable }
            return try device.makeComputePipelineState(function: function)
        }
        reset = try pipeline("gg_reset")
        seed = try pipeline("gg_seed")
        flood = try pipeline("gg_flood")
        distance = try pipeline("gg_distance")
        smooth = try pipeline("gg_smooth")
        shade = try pipeline("gg_shade")
        blur = try pipeline("gg_blur")
        compose = try pipeline("gg_compose")
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        guard let black = device.makeTexture(descriptor: d) else { throw GlassGlowError.metalUnavailable }
        var zero = [UInt16](repeating: 0, count: 4)
        black.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 8)
        self.black = black
    }
}

public enum GlassGlowError: Error {
    /// The device has no Metal GPU, or the shaders failed to compile.
    case metalUnavailable
}

/// One effect's working textures. The distance field is rebuilt only when the mask changes;
/// every frame shades the glass, blurs the halo and composes into the target.
final class GlowCanvas {
    private struct Params {
        var a: SIMD4<Float>
        var b: SIMD4<Float>
        var c: SIMD4<Float>
        var gamma: SIMD4<Float>
        var rimColour: SIMD4<Float>
        var band: SIMD4<Float>
        var info: SIMD4<UInt32>
    }

    private struct Blob {
        var pos: SIMD4<Float>
        var shape: SIMD4<Float>
        var colour: SIMD4<Float>
    }

    /// Shapes wider than this (width / height) stretch the lights sideways to reach both ends.
    private static let stretchAspect: Float = 0.9

    let pipelines: GlowPipelines
    private let box: MTLBuffer
    private(set) var width = 0
    private(set) var height = 0
    private var maskBytes: [UInt8] = []
    private var maskDirty = false
    private var mask: MTLTexture?
    private var seedsA: MTLTexture?
    private var seedsB: MTLTexture?
    private var sdf: MTLTexture?
    private var sdfRaw: MTLTexture?
    private var glass: MTLTexture?
    private var base: MTLTexture?
    private var blurTemp: [MTLTexture] = []
    private var blurOut: [MTLTexture] = []
    private var blurLevels: [Int] = []

    init(pipelines: GlowPipelines) throws {
        self.pipelines = pipelines
        guard let box = pipelines.device.makeBuffer(length: 16, options: [.storageModeShared]) else { throw GlassGlowError.metalUnavailable }
        self.box = box
    }

    var hasMask: Bool { mask != nil }
    /// True until a frame has measured the new mask's box (the halo's mip levels depend on it).
    var needsMeasuring: Bool { maskDirty }

    /// Sets the shape: the alpha of `image`, which also sets the canvas size.
    /// An identical mask keeps the current distance field.
    func setMask(_ image: CGImage) {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        if w == width, h == height, bytes == maskBytes, mask != nil { return }
        if w != width || h != height || mask == nil { allocate(w, h) }
        maskBytes = bytes
        mask?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w)
        maskDirty = true
    }

    private func texture(_ w: Int, _ h: Int, _ format: MTLPixelFormat, mipmapped: Bool = false, shared: Bool = false) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(1, w), height: max(1, h), mipmapped: mipmapped)
        d.usage = [.shaderRead, .shaderWrite]
        if !shared { d.storageMode = .private }
        return pipelines.device.makeTexture(descriptor: d)
    }

    private func allocate(_ w: Int, _ h: Int) {
        width = w
        height = h
        mask = texture(w, h, .r8Unorm, shared: true)
        seedsA = texture(w, h, .rgba32Float)
        seedsB = texture(w, h, .rgba32Float)
        sdf = texture(w, h, .r32Float)
        sdfRaw = texture(w, h, .r32Float)
        glass = texture(w, h, .rgba16Float, mipmapped: true)
        base = texture(w, h, .rgba16Float)
        blurLevels = []
        let v = box.contents().bindMemory(to: UInt32.self, capacity: 4)
        v[0] = 0; v[1] = 0; v[2] = 0; v[3] = 0
    }

    /// The mip level each bloom radius runs on, chosen so the blur is about 4-16 texels wide there.
    private func levels(maxLevel: Int) -> [Int] {
        let v = box.contents().bindMemory(to: UInt32.self, capacity: 4)
        let boxHeight = v[3] > v[1] && v[1] != .max ? Float(v[3] - v[1]) : Float(height) * 0.6
        return LightModel.bloom.map { b in
            let sigma = b.radius * boxHeight
            return min(maxLevel, max(0, Int(floor(log2(max(sigma, 1) / 4)))))
        }
    }

    private func dispatch(_ enc: MTLComputeCommandEncoder, _ pso: MTLComputePipelineState, _ w: Int, _ h: Int) {
        enc.setComputePipelineState(pso)
        let tw = pso.threadExecutionWidth
        let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
        enc.dispatchThreadgroups(MTLSize(width: (w + tw - 1) / tw, height: (h + th - 1) / th, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    /// Encodes one frame at loop time `time` (seconds) into `target`, which must match the mask's
    /// size and allow shader writes.
    func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer, time: Float, style: ResolvedStyle) {
        guard let mask, let seedsA, let seedsB, let sdf, let sdfRaw, let glass, let base,
              target.width == width, target.height == height else { return }
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))

        if maskDirty, let enc = commandBuffer.makeComputeCommandEncoder() {
            maskDirty = false
            enc.label = "GlassGlow distance field"
            enc.setBuffer(box, offset: 0, index: 0)
            enc.setComputePipelineState(pipelines.reset)
            enc.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            enc.setTexture(mask, index: 0)
            enc.setTexture(seedsA, index: 1)
            enc.setBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
            dispatch(enc, pipelines.seed, width, height)
            // Jump flood from half the larger side down to 1, plus one extra 1-step pass.
            var steps: [Int] = []
            var s = 1
            while s < max(width, height) { s <<= 1 }
            s >>= 1
            while s >= 1 { steps.append(s); s >>= 1 }
            steps.append(1)
            var src = seedsA, dst = seedsB
            for step in steps {
                var sizeStep = SIMD3<Int32>(Int32(width), Int32(height), Int32(step))
                enc.setTexture(src, index: 0)
                enc.setTexture(dst, index: 1)
                enc.setBytes(&sizeStep, length: MemoryLayout<SIMD3<Int32>>.stride, index: 0)
                dispatch(enc, pipelines.flood, width, height)
                swap(&src, &dst)
            }
            enc.setTexture(mask, index: 0)
            enc.setTexture(src, index: 1)
            enc.setTexture(sdfRaw, index: 2)
            enc.setBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 0)
            dispatch(enc, pipelines.distance, width, height)
            enc.setTexture(sdfRaw, index: 0)
            enc.setTexture(sdf, index: 1)
            dispatch(enc, pipelines.smooth, width, height)
            enc.endEncoding()
        }

        let wanted = levels(maxLevel: glass.mipmapLevelCount - 1)
        if wanted != blurLevels {
            blurLevels = wanted
            blurTemp = []
            blurOut = []
            for level in wanted {
                let w = max(1, width >> level), h = max(1, height >> level)
                guard let t = texture(w, h, .rgba16Float), let o = texture(w, h, .rgba16Float) else { return }
                blurTemp.append(t)
                blurOut.append(o)
            }
        }

        let blobs = LightModel.blobs(at: time, colours: style.colours).map {
            Blob(pos: SIMD4($0.x, $0.y, $0.z, $0.radius), shape: SIMD4($0.intensity, $0.aspect, cos($0.angle), sin($0.angle)), colour: SIMD4($0.colour, 0))
        }
        let m = LightModel.self
        var params = Params(
            a: SIMD4(m.height, m.contrast, m.edgeSoftness, m.dispersion * style.dispersion),
            b: SIMD4(m.bevelWidth, m.bevelRefraction * style.refraction, m.bevelExponent, m.rimWidth),
            c: SIMD4(m.rimAmbient, m.rimLight, m.rimInset, style.intensity),
            gamma: SIMD4(m.gamma, Self.stretchAspect),
            rimColour: SIMD4(m.rimColour, 0),
            band: SIMD4(m.bandInset, m.bandWidth, m.bandLight, m.bandBlur * m.bandBlur),
            info: SIMD4(UInt32(width), UInt32(height), UInt32(blobs.count), 0))

        guard let enc = commandBuffer.makeComputeCommandEncoder() else { return }
        enc.label = "GlassGlow shade"
        enc.setTexture(sdf, index: 0)
        enc.setTexture(glass, index: 1)
        enc.setTexture(base, index: 2)
        enc.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        enc.setBytes(blobs, length: MemoryLayout<Blob>.stride * blobs.count, index: 1)
        enc.setBuffer(box, offset: 0, index: 2)
        dispatch(enc, pipelines.shade, width, height)
        enc.endEncoding()

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: glass)
            blit.endEncoding()
        }

        guard let enc2 = commandBuffer.makeComputeCommandEncoder() else { return }
        enc2.label = "GlassGlow halo + compose"
        for (i, level) in blurLevels.enumerated() {
            guard let view = glass.makeTextureView(pixelFormat: glass.pixelFormat, textureType: .type2D, levels: level..<(level + 1), slices: 0..<1) else { continue }
            let w = blurOut[i].width, h = blurOut[i].height
            let scale = Float(w) / Float(width)
            for (input, out, dir) in [(view, blurTemp[i], SIMD2<Float>(1, 0)), (blurTemp[i], blurOut[i], SIMD2<Float>(0, 1))] {
                var p = SIMD4<Float>(dir.x, dir.y, m.bloom[i].radius, scale)
                enc2.setTexture(input, index: 0)
                enc2.setTexture(out, index: 1)
                enc2.setBytes(&p, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                enc2.setBuffer(box, offset: 0, index: 1)
                enc2.setBytes(&params, length: MemoryLayout<Params>.stride, index: 2)
                dispatch(enc2, pipelines.blur, w, h)
            }
        }
        var gains = SIMD4<Float>(m.bloom[0].gain * style.glow, m.bloom[1].gain * style.glow, m.bloom[2].gain * style.glow, 0)
        enc2.setTexture(base, index: 0)
        for i in 0..<3 { enc2.setTexture(i < blurOut.count ? blurOut[i] : pipelines.black, index: 1 + i) }
        enc2.setTexture(target, index: 4)
        enc2.setBytes(&gains, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc2.setBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
        dispatch(enc2, pipelines.compose, width, height)
        enc2.endEncoding()
    }
}
