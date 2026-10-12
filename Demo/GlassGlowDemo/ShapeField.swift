import CoreGraphics
import Metal

/// Draws the film's shapes as one alpha mask from their signed distance fields, so shapes morph
/// and melt without popping.
///
/// Elements in one group interpolate their distances (a morph). Groups join with a smooth union
/// (`melt` pixels wide), so shapes near each other flow together like liquid. A group's presence
/// below 1 shrinks it until it is gone.
final class ShapeField {
    struct Element {
        var shape: Int
        var group: Int
        /// Centre in pixels, y down.
        var center: SIMD2<Float>
        /// Output pixels per field pixel.
        var scale: Float
        /// Interpolation weight inside the group.
        var weight: Float
    }

    struct Group {
        var presence: Float
        /// How far the group shrinks at presence 0, in pixels.
        var radius: Float
    }

    private struct GPUElement {
        var center: SIMD2<Float>
        var scale: Float
        var weight: Float
        var shape: Int32
        var group: Int32
        var pad: SIMD2<Int32> = .zero
    }

    static let maxShapes = 8
    static let maxElements = 16
    static let maxGroups = 8

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var fields: [MTLTexture] = []
    private var target: MTLTexture?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil),
              let function = library.makeFunction(name: "shape_field"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    /// Adds a shape from the alpha of `image` and returns its index. Distances are in the image's
    /// pixels, measured from its centre.
    @discardableResult
    func add(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var alpha = [UInt8](repeating: 0, count: w * h)
        alpha.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let distance = Self.signedDistance(alpha, w, h)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: d)!
        distance.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 4) }
        fields.append(texture)
        return fields.count - 1
    }

    func size(of shape: Int) -> CGSize { CGSize(width: fields[shape].width, height: fields[shape].height) }

    /// The mask at `width` x `height`: white with the shapes in its alpha.
    func mask(width: Int, height: Int, elements: [Element], groups: [Group], melt: Float) -> CGImage? {
        if target?.width != width || target?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            d.usage = [.shaderWrite]
            d.storageMode = .shared
            target = device.makeTexture(descriptor: d)
        }
        guard let target, let commandBuffer = queue.makeCommandBuffer(), let enc = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var list = elements.prefix(Self.maxElements).map {
            GPUElement(center: $0.center, scale: $0.scale, weight: $0.weight, shape: Int32($0.shape), group: Int32($0.group))
        }
        if list.isEmpty { list.append(GPUElement(center: .zero, scale: 1, weight: 0, shape: 0, group: 0)) }
        var gpuGroups = groups.prefix(Self.maxGroups).map { SIMD2($0.presence, $0.radius) }
        if gpuGroups.isEmpty { gpuGroups.append(.zero) }
        var counts = SIMD4<Int32>(Int32(elements.count), Int32(groups.count), 0, 0)
        var melt = melt
        enc.setComputePipelineState(pipeline)
        for (i, field) in fields.prefix(Self.maxShapes).enumerated() { enc.setTexture(field, index: i) }
        enc.setTexture(target, index: Self.maxShapes)
        enc.setBytes(&list, length: MemoryLayout<GPUElement>.stride * list.count, index: 0)
        enc.setBytes(&gpuGroups, length: MemoryLayout<SIMD2<Float>>.stride * gpuGroups.count, index: 1)
        enc.setBytes(&counts, length: MemoryLayout<SIMD4<Int32>>.stride, index: 2)
        enc.setBytes(&melt, length: 4, index: 3)
        let tw = pipeline.threadExecutionWidth, th = pipeline.maxTotalThreadsPerThreadgroup / tw
        enc.dispatchThreadgroups(MTLSize(width: (width + tw - 1) / tw, height: (height + th - 1) / th, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        enc.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Signed distance to the 50% alpha edge, positive inside (Felzenszwalb's exact transform).
    private static func signedDistance(_ alpha: [UInt8], _ w: Int, _ h: Int) -> [Float] {
        let inside = alpha.map { $0 >= 128 }
        let toInside = transform(inside.map { $0 ? 0 : Float.greatestFiniteMagnitude }, w, h)
        let toOutside = transform(inside.map { $0 ? Float.greatestFiniteMagnitude : 0 }, w, h)
        return (0..<(w * h)).map { i in
            inside[i] ? toOutside[i].squareRoot() - 0.5 : -(toInside[i].squareRoot() - 0.5)
        }
    }

    /// Squared Euclidean distance transform of `f` (0 at seeds, infinity elsewhere).
    private static func transform(_ f: [Float], _ w: Int, _ h: Int) -> [Float] {
        var g = f
        var column = [Float](repeating: 0, count: h)
        for x in 0..<w {
            for y in 0..<h { column[y] = g[y * w + x] }
            let d = transform1D(column)
            for y in 0..<h { g[y * w + x] = d[y] }
        }
        for y in 0..<h {
            let d = transform1D(Array(g[(y * w)..<(y * w + w)]))
            g.replaceSubrange((y * w)..<(y * w + w), with: d)
        }
        return g
    }

    private static func transform1D(_ f: [Float]) -> [Float] {
        let n = f.count
        let inf = Float.greatestFiniteMagnitude
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = -1
        for q in 0..<n where f[q] < inf {
            let fq = f[q] + Float(q * q)
            if k < 0 {
                k = 0; v[0] = q; z[0] = -inf; z[1] = inf
                continue
            }
            var s: Float
            repeat {
                let p = v[k]
                s = (fq - (f[p] + Float(p * p))) / Float(2 * (q - p))
                if s <= z[k] { k -= 1 } else { break }
            } while k >= 0
            k += 1
            v[k] = q; z[k] = s; z[k + 1] = inf
        }
        if k < 0 { return [Float](repeating: inf, count: n) }
        var j = 0
        for q in 0..<n {
            while z[j + 1] < Float(q) { j += 1 }
            let dq = Float(q - v[j])
            d[q] = dq * dq + f[v[j]]
        }
        return d
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Element { float2 center; float scale; float weight; int shape; int group; int2 pad; };

    kernel void shape_field(uint2 gid [[thread_position_in_grid]],
                            array<texture2d<float, access::sample>, 8> fields [[texture(0)]],
                            texture2d<float, access::write> out [[texture(8)]],
                            constant Element* elements [[buffer(0)]],
                            constant float2* groups [[buffer(1)]],
                            constant int4& counts [[buffer(2)]],
                            constant float& melt [[buffer(3)]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        constexpr sampler s(filter::linear, address::clamp_to_edge, coord::pixel);
        float2 p = float2(gid) + 0.5f;
        float sum[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        for (int i = 0; i < counts.x; i++) {
            Element e = elements[i];
            texture2d<float, access::sample> f = fields[e.shape];
            float2 size = float2(f.get_width(), f.get_height());
            float2 q = (p - e.center) / e.scale + size * 0.5f;
            sum[e.group] += e.weight * f.sample(s, q).r * e.scale;
        }
        // Smooth union of the groups: shapes within `melt` pixels flow together.
        float d = -1e6f;
        for (int g = 0; g < counts.y; g++) {
            float dg = sum[g] - (1.0f - groups[g].x) * groups[g].y;
            if (groups[g].x <= 0.0f) continue;
            float k = max(melt, 1e-3f);
            float h = max(k - abs(d - dg), 0.0f) / k;
            d = max(d, dg) + h * h * k * 0.25f;
        }
        float a = clamp(d + 0.5f, 0.0f, 1.0f);
        out.write(float4(a), gid);
    }
    """
}
