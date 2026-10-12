import CoreGraphics
import SwiftUI
import Testing
@testable import GlassGlow

/// Reads straight RGB (0...1) out of a premultiplied RGBA8 image.
private struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.bytes = bytes
    }

    /// The colour over black (the premultiplied value), x and y from the top left in 0...1.
    func rgb(_ x: Double, _ y: Double) -> SIMD3<Float> {
        let px = min(width - 1, Int(x * Double(width))), py = min(height - 1, Int(y * Double(height)))
        let i = (py * width + px) * 4
        return SIMD3(Float(bytes[i]), Float(bytes[i + 1]), Float(bytes[i + 2])) / 255
    }

    func luma(_ x: Double, _ y: Double) -> Float {
        let c = rgb(x, y)
        return (c.x + c.y + c.z) / 3
    }

    /// Mean colour over the centre square of side `fraction`.
    func mean(fraction: Double) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        var n: Float = 0
        for j in 0..<16 {
            for i in 0..<16 {
                let x = 0.5 - fraction / 2 + fraction * (Double(i) + 0.5) / 16
                let y = 0.5 - fraction / 2 + fraction * (Double(j) + 0.5) / 16
                sum += rgb(x, y)
                n += 1
            }
        }
        return sum / n
    }
}

@MainActor
@Suite("GlassGlow", .serialized)
struct GlassGlowTests {
    var circle: some View { Circle().frame(width: 200, height: 200) }
    let size = CGSize(width: 200, height: 200)

    private func render(_ style: GlassGlowStyle = .default, time: Double) throws -> Pixels {
        let renderer = try GlassGlowRenderer()
        return Pixels(try #require(renderer.image(of: circle, size: size, scale: 1, style: style, time: time)))
    }

    @Test("lights the shape, leaves the far corner dark and draws a halo")
    func lightsShape() throws {
        let p = try render(time: 0)
        let margin = GlassGlowRenderer.margin(for: size)
        #expect(p.width == Int(size.width + 2 * margin))
        #expect(p.mean(fraction: 0.3).max() > 0.2)
        #expect(p.luma(0.01, 0.01) < 0.02)
        // Just above the circle's top edge.
        let top = Double(margin - 6) / Double(p.height)
        #expect(p.luma(0.5, top) > p.luma(0.01, 0.01) + 0.02)
    }

    @Test("loops every 6 seconds at speed 1, and speed scales time")
    func loops() throws {
        let a = try render(time: 1.3)
        let b = try render(time: 7.3)
        let c = try render(time: 3.3)
        let fast = try render(GlassGlowStyle(speed: 2), time: 0.65)
        var diffLoop: Float = 0, diffOther: Float = 0, diffFast: Float = 0
        for j in 0..<24 {
            for i in 0..<24 {
                let x = (Double(i) + 0.5) / 24, y = (Double(j) + 0.5) / 24
                diffLoop = max(diffLoop, abs(a.luma(x, y) - b.luma(x, y)))
                diffOther = max(diffOther, abs(a.luma(x, y) - c.luma(x, y)))
                diffFast = max(diffFast, abs(a.luma(x, y) - fast.luma(x, y)))
            }
        }
        #expect(diffLoop < 0.02)
        #expect(diffFast < 0.02)
        #expect(diffOther > 0.1)
    }

    @Test("the palette sets the hue of the light")
    func palette() throws {
        var warm = SIMD3<Float>(repeating: 0), cool = SIMD3<Float>(repeating: 0)
        for t in stride(from: 0.0, to: 6, by: 1.5) {
            warm += try render(GlassGlowStyle(palette: GlassGlowPalette(Color(red: 1, green: 0.1, blue: 0))), time: t).mean(fraction: 0.6)
            cool += try render(GlassGlowStyle(palette: GlassGlowPalette(Color(red: 0, green: 0.1, blue: 1))), time: t).mean(fraction: 0.6)
        }
        #expect(warm.x > warm.z * 2)
        #expect(cool.z > cool.x * 2)
    }

    @Test("glow 0 removes the halo")
    func glowOff() throws {
        let margin = GlassGlowRenderer.margin(for: size)
        let on = try render(time: 0)
        let off = try render(GlassGlowStyle(glow: 0), time: 0)
        let y = Double(margin - 20) / Double(on.height)
        #expect(off.luma(0.5, y) < on.luma(0.5, y))
        #expect(off.luma(0.5, y) < 0.01)
    }

    @Test("wide shapes are lit end to end")
    func wideShape() throws {
        let renderer = try GlassGlowRenderer()
        let bar = Capsule().frame(width: 800, height: 100)
        var left: Float = 0, right: Float = 0
        for t in stride(from: 0.0, to: 6, by: 0.5) {
            let p = Pixels(try #require(renderer.image(of: bar, size: CGSize(width: 800, height: 100), scale: 1, time: t)))
            let m = Double(GlassGlowRenderer.margin(for: CGSize(width: 800, height: 100)))
            let w = Double(p.width)
            left = max(left, p.luma((m + 120) / w, 0.5))
            right = max(right, p.luma((w - m - 120) / w, 0.5))
        }
        #expect(left > 0.15)
        #expect(right > 0.15)
    }

    @Test("ImageRenderer captures the effect with glassGlowSnapshot")
    func snapshot() throws {
        let view = circle
            .glassGlow()
            .padding(100)
            .background(Color.black)
            .glassGlowSnapshot(at: 0)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let p = Pixels(try #require(renderer.cgImage))
        #expect(p.width == 400)
        #expect(p.mean(fraction: 0.15).max() > 0.2)
        #expect(p.luma(0.01, 0.01) < 0.02)
    }
}
